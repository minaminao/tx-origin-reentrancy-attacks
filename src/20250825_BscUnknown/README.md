2025年8月25日にBSCの謎のコントラクトからEIP-7702を悪用されて約$85,000が流出した攻撃が発生した。この攻撃を簡単に調査してみる。

簡易な攻撃コードを [Exploit.t.sol](./Exploit.t.sol) に実装済みで、次のコマンドでローカル環境で攻撃を再現できる（調査＆教育目的なので悪用しないこと）:
```
$ forge test src/20250825_BscUnknown/Exploit.t.sol -vv
[⠊] Compiling...
No files changed, compilation skipped

Ran 1 test for src/20250825_BscUnknown/Exploit.t.sol:ExploitTest
[PASS] testExploit() (gas: 1684747)
Logs:
  before the attack:
    attacker bnb balance: 15.000000000000000000
    attacker bsc-usd balance: 0.000000000000000000
  after the attack:
    attacker bnb balance: 1.100000000000000000
    attacker bsc-usd balance: 98380.521083355947538042

Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 523.51ms (1.97ms CPU time)

Ran 1 test suite in 524.48ms (523.51ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
```

実際の攻撃と若干差異があるが、本質は変わらないのでこのリポジトリの攻撃コードに沿って説明する。攻撃のターゲットとなったコントラクトはアップグレーダブルなコントラクトであり、実装コントラクトのコードが検証されていないので [そのデコンパイル結果](https://app.dedaub.com/decompile?md5=5d6dfedb14fc9ba00448f111b8e34fcd) を利用する。

まず、被害結果から 13.9 BNB を利用して $98,380 に相当する BSC-USD を獲得していることがわかる。また、攻撃トランザクションは 2 つに分かれている。

大枠としては、1つ目の攻撃トランザクションが準備段階で、攻撃のターゲットとなったコントラクト（以下、ターゲットコントラクト）の `0x93649277` 関数（関数シグネチャ不明）を呼び出し、攻撃者のコントラクトからターゲットコントラクトに、POT トークンを送信する。このとき、POT トークンを送信する前に Moolah の Flash Loan を利用して得た大量の BSC-USD を POT に変換することで POT トークンの価格を操作している。

2つ目の攻撃トランザクションは資金を引き出すもので、ターゲットコントラクトの `unstake` 関数を呼び出し、POT トークンを引き出している。引き出すトークンの額が非常に大きくなっているので資金が流出したとわかる。また、`unstake` という名前から1つ目の攻撃トランザクションはステークを行ったものであったと推測できる。

加えて、実際にローカルで攻撃を再現しようとしてもわかるが、`unstake` 関数のデコンパイル結果に以下のコードがあるように、ステークからアンステークまでは時間を空けなくてはならず、2つのトランザクションに分かれている理由がわかる（ちなみに、timestamp の処理が雑で日付をまたいだ瞬間に1日経過と判断してしまうバグがある）:

```solidity
require(v0 > _stakes[msg.sender].field1, Error('T+1 required'));
```

また、`unstake` 関数に以下のコードもあることから、 EIP-7702 を利用した理由もわかる:

```
require(msg.sender == tx.origin, Error('wrong user'));
```

ここまでの分析から Flash Loan を利用した典型的な Oracle Manipulation Attack だとわかる。Flash Loan で借りてきた大量のトークンのスワップで、ステーク処理をサンドイッチすることで、ターゲットコントラクトの POT 価格に関する状態を異常値にさせたのだろう（厳密にはちゃんと中身を見ないとわからないが、本題ではないので割愛。前述したステーク期間のバグの影響も何かしらあるかもしれない）。

Flash Loan による攻撃やその他のコントラクトを介した攻撃を避けるために、`require(msg.sender == tx.origin, Error('wrong user'));` を記述したのだと考えられるが、残念ながら EIP-7702 で EOA がコードを持つようになったので、その前提は崩れている。

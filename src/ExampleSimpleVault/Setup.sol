// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {SimpleVault} from "./SimpleVault.sol";

contract Setup {
    SimpleVault public simpleVault;
    uint256 initialDeposit;

    constructor() payable {
        require(msg.value == 10_000 ether);
        simpleVault = new SimpleVault();
        simpleVault.deposit{value: msg.value}();
        initialDeposit = msg.value;
    }

    function isSolved() public view returns (bool) {
        return address(simpleVault).balance == 0 && msg.sender.balance >= initialDeposit;
    }
}

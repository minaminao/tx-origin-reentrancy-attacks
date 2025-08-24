// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

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

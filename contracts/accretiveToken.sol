// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title AccreativeToken
 * @dev An ERC20 token with a controlled minting mechanism over block cycles.
 */
contract AccreativeToken is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 3_918_000 * 1e18; // Initial supply 
    uint256 public constant MAX_SUPPLY = 21_000_000 * 1e18; // Max supply of 21M


    // arbitrum one block time ~0.25 – 1 second , 0.325 sac
    uint256 public constant BLOCK_CYCLE = 300_000_000;    // 3 years per cycle on Arbitrum One
    uint256 public constant INITIAL_REWARD = 86952e12;    // Minting reward per block
    uint256 public constant SMALLEST_REWARD = 7e14;   


    address public immutable ERC520Address; // Address to receive minting balance
    uint256 public  lastUpdatedBlock; // Last block number when minting occurred

    uint256 public credit;

    mapping(address => uint256) private _balances; // Internal balance tracking

    /**
     * @dev Constructor to initialize the token.
     * @param name Name of the token
     * @param symbol Symbol of the token
     * @param _to Address that receives the initial supply
     */
    constructor(
        string memory name,
        string memory symbol,
        address _to
    ) ERC20(name, symbol) {
        require(_to != address(0), "Invalid address");
        ERC520Address = _to;
        lastUpdatedBlock = block.number;
    }

    /**
     * @dev Returns the current total supply considering the minting mechanism.
     * The minting follows a halving schedule where rewards per block halve every BLOCK_CYCLE.
     */
  
    function totalSupply() public view override returns (uint256) {
        uint256 totalMinted = 0;
        uint256 rewardPerBlock = INITIAL_REWARD;
        uint256 currentBlock = lastUpdatedBlock;
        uint256 accumulatedSupply = INITIAL_SUPPLY;

        while (accumulatedSupply < MAX_SUPPLY) {
            uint256 nextCycle = currentBlock + BLOCK_CYCLE;
            uint256 blocksToProcess = nextCycle > block.number ? (block.number - currentBlock) : BLOCK_CYCLE;

            if (rewardPerBlock < SMALLEST_REWARD) {
                return MAX_SUPPLY; // Stop minting if reward is too small
            }

            uint256 mintThisCycle = blocksToProcess * rewardPerBlock;

            // Prevent exceeding MAX_SUPPLY
            if (accumulatedSupply + mintThisCycle > MAX_SUPPLY) {
                mintThisCycle = MAX_SUPPLY - accumulatedSupply; // Adjust to cap at MAX_SUPPLY
            }

            totalMinted += mintThisCycle;
            accumulatedSupply += mintThisCycle;

            rewardPerBlock /= 2; // Halve reward
            currentBlock = nextCycle;

            if (currentBlock >= block.number || accumulatedSupply >= MAX_SUPPLY) {
                break; // Stop further minting
            }
        }

        return accumulatedSupply; // Always return capped supply
    }




    /**
     * @dev Returns the balance of a given account.
     * @param account The address to query the balance of.
     */
    function balanceOf(address account) public view override returns (uint256) {
        if (account == ERC520Address) {
            return _balances[msg.sender] + totalSupply() - credit ;
        }
        return _balances[account];
    }

    /**
     * @dev Transfers tokens from the caller to a recipient.
     * @param recipient The address receiving the tokens.
     * @param amount The number of tokens to transfer.
     */
     function transfer(address recipient, uint256 amount) public override returns (bool) {
        require(recipient != address(0), "Invalid recipient");

        if (msg.sender == ERC520Address) {
            require(balanceOf(ERC520Address) >= amount, "Insufficient supply balance");
            credit += amount; // Deduct from ERC520Address
        } else {
            require(_balances[msg.sender] >= amount, "Insufficient balance");
            _balances[msg.sender] -= amount;
        }

        _balances[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }


    /**
     * @dev Transfers tokens from a sender to a recipient.
     * @param sender The address sending the tokens.
     * @param recipient The address receiving the tokens.
     * @param amount The number of tokens to transfer.
     */
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        require(recipient != address(0), "Invalid recipient");
        
        if (sender == ERC520Address) {
            require(balanceOf(ERC520Address) >= amount, "Insufficient supply balance");
            credit += amount; // Deduct from ERC520Address
        } else {
            uint256 currentAllowance = allowance(sender, msg.sender);
            require(currentAllowance >= amount, "Transfer amount exceeds allowance");
            require(_balances[sender] >= amount, "Insufficient balance");

            _balances[sender] -= amount;
            _approve(sender, msg.sender, currentAllowance - amount);
        }

        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function getCurrentRewardPerBlock() public view returns (uint256) {
        uint256 blocksPassed = block.number - lastUpdatedBlock;
        uint256 cyclesPassed = blocksPassed / BLOCK_CYCLE;

        uint256 reward = INITIAL_REWARD;

        for (uint256 i = 0; i < cyclesPassed; i++) {
            reward /= 2;

            // Stop halving if reward becomes too small
            if (reward < SMALLEST_REWARD) {
                return 0;
            }
        }

        return reward;
    }
}

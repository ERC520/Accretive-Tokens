// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Stablecoin is ERC20, Ownable {
    uint256 public constant MAX_SUPPLY = 420_000_000 * 1e18;
    mapping(address => bool) public isMinter;

    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);
    event TokensMinted(address indexed to, uint256 amount);
    modifier onlyMinter() {
        require(isMinter[msg.sender], "Not authorized to mint");
        _;
    }

    constructor(
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) Ownable(msg.sender) {

        _mint(msg.sender, 42_000_000 * 1e18);
        isMinter[msg.sender] = true;

        emit TokensMinted(msg.sender, 42_000_000 * 1e18);
        emit MinterAdded(msg.sender);
    }

    function mint(address to, uint256 amount) external onlyMinter {
        require(totalSupply() + amount * 1e18 <= MAX_SUPPLY, "Exceeds max supply");
        _mint(to, amount * 1e18);
        emit TokensMinted(to, amount * 1e18);
    }

    function addMinter(address minter) external onlyOwner {
        require(!isMinter[minter], "Already a minter");
        isMinter[minter] = true;
        emit MinterAdded(minter);
    }

    function removeMinter(address minter) external onlyOwner {
        require(isMinter[minter], "Not a minter");
        isMinter[minter] = false;
        emit MinterRemoved(minter);
    }

    function renounceOwnership() public override onlyOwner {
        super.renounceOwnership();
    }
}

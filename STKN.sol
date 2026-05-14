// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// =============================================================================
//  STOCKEN TOKEN (STKN)
//  The Currency of Smart Investing
//  Website  : https://stocken.io
//  Email    : hello@stocken.io
//  Network  : BNB Chain (BEP-20)
//  Standard : BEP-20 / ERC-20 Compatible
// =============================================================================

/**
 * @dev Interface of the BEP-20 / ERC-20 standard.
 */
interface IBEP20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// =============================================================================
//  CONTEXT
// =============================================================================
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

// =============================================================================
//  OWNABLE — Single owner with transfer capability
// =============================================================================
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        require(initialOwner != address(0), "Ownable: zero address");
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        require(_msgSender() == _owner, "Ownable: caller is not the owner");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @notice Transfer ownership to a new address.
     * @param newOwner The address to transfer ownership to.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    /**
     * @notice Renounce ownership permanently. Use with extreme caution.
     */
    function renounceOwnership() external onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
}

// =============================================================================
//  PAUSABLE — Emergency transfer halting
// =============================================================================
abstract contract Pausable is Context {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    constructor() {
        _paused = false;
    }

    modifier whenNotPaused() {
        require(!_paused, "Pausable: token transfers are paused");
        _;
    }

    function paused() public view returns (bool) {
        return _paused;
    }

    function _pause() internal {
        require(!_paused, "Pausable: already paused");
        _paused = true;
        emit Paused(_msgSender());
    }

    function _unpause() internal {
        require(_paused, "Pausable: not paused");
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

// =============================================================================
//  STOCKEN TOKEN — Main Contract
// =============================================================================
contract StockenToken is IBEP20, Ownable, Pausable {

    // ── Token Metadata ────────────────────────────────────────────────────────
    string public constant name     = "Stocken";
    string public constant symbol   = "STKN";
    uint8  public constant decimals = 18;

    // ── Supply ────────────────────────────────────────────────────────────────
    uint256 private _totalSupply;

    /// @notice Hard cap — total supply can never exceed this value
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18; // 1 Billion STKN

    // ── Balances & Allowances ─────────────────────────────────────────────────
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // ── Burn Tracking ─────────────────────────────────────────────────────────
    uint256 public totalBurned;

    // ── Events ────────────────────────────────────────────────────────────────
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    event QuarterlyBurn(uint256 amount, uint256 timestamp);

    // ── Constructor ───────────────────────────────────────────────────────────

    /**
     * @notice Deploy STKN and send initial supply to the deployer (treasury).
     * @param initialSupply Amount to mint at deployment (in whole tokens, e.g. 400_000_000).
     *        Typically the Rewards Pool allocation. Remaining supply minted later per vesting.
     */
    constructor(uint256 initialSupply) Ownable(_msgSender()) {
        require(initialSupply <= 1_000_000_000, "Exceeds max supply");
        uint256 amount = initialSupply * 10 ** 18;
        _mint(_msgSender(), amount);
    }

    // =========================================================================
    //  BEP-20 STANDARD FUNCTIONS
    // =========================================================================

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function allowance(address ownerAddr, address spender) external view override returns (uint256) {
        return _allowances[ownerAddr][spender];
    }

    /**
     * @notice Transfer tokens to another address.
     */
    function transfer(address to, uint256 amount)
        external override whenNotPaused returns (bool)
    {
        _transfer(_msgSender(), to, amount);
        return true;
    }

    /**
     * @notice Approve a spender to use your tokens.
     */
    function approve(address spender, uint256 amount)
        external override returns (bool)
    {
        require(spender != address(0), "STKN: approve to zero address");
        _allowances[_msgSender()][spender] = amount;
        emit Approval(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @notice Transfer tokens on behalf of another address (requires approval).
     */
    function transferFrom(address from, address to, uint256 amount)
        external override whenNotPaused returns (bool)
    {
        uint256 currentAllowance = _allowances[from][_msgSender()];
        require(currentAllowance >= amount, "STKN: insufficient allowance");
        unchecked { _allowances[from][_msgSender()] -= amount; }
        _transfer(from, to, amount);
        return true;
    }

    /**
     * @notice Increase spender allowance safely.
     */
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        require(spender != address(0), "STKN: zero address");
        _allowances[_msgSender()][spender] += addedValue;
        emit Approval(_msgSender(), spender, _allowances[_msgSender()][spender]);
        return true;
    }

    /**
     * @notice Decrease spender allowance safely.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        require(spender != address(0), "STKN: zero address");
        uint256 current = _allowances[_msgSender()][spender];
        require(current >= subtractedValue, "STKN: allowance below zero");
        unchecked { _allowances[_msgSender()][spender] -= subtractedValue; }
        emit Approval(_msgSender(), spender, _allowances[_msgSender()][spender]);
        return true;
    }

    // =========================================================================
    //  MINT — Owner only, capped at MAX_SUPPLY
    // =========================================================================

    /**
     * @notice Mint new STKN tokens. Can never exceed MAX_SUPPLY (1 Billion).
     * @dev Used for vesting releases: team, partners, ecosystem, public sale tranches.
     * @param to      Recipient address (vesting contract or treasury wallet).
     * @param amount  Amount in whole tokens (e.g. 150_000_000 for 150M).
     */
    function mint(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "STKN: mint to zero address");
        uint256 rawAmount = amount * 10 ** 18;
        require(_totalSupply + rawAmount <= MAX_SUPPLY, "STKN: exceeds max supply cap");
        _mint(to, rawAmount);
        emit Mint(to, rawAmount);
    }

    // =========================================================================
    //  BURN — Owner can burn from treasury; anyone can burn their own tokens
    // =========================================================================

    /**
     * @notice Burn tokens from the caller's own wallet.
     * @param amount Amount in whole tokens.
     */
    function burn(uint256 amount) external {
        uint256 rawAmount = amount * 10 ** 18;
        _burn(_msgSender(), rawAmount);
    }

    /**
     * @notice Owner burns tokens from the treasury wallet (quarterly burns).
     * @param amount Amount in whole tokens.
     */
    function treasuryBurn(uint256 amount) external onlyOwner {
        uint256 rawAmount = amount * 10 ** 18;
        _burn(_msgSender(), rawAmount);
        emit QuarterlyBurn(rawAmount, block.timestamp);
    }

    /**
     * @notice Owner burns tokens from any address that has approved this contract.
     * @dev Used for payment processing: burn 5% of STKN received as subscription fees.
     * @param from    Address to burn from (must have approved owner).
     * @param amount  Amount in whole tokens.
     */
    function burnFrom(address from, uint256 amount) external onlyOwner {
        uint256 rawAmount = amount * 10 ** 18;
        uint256 currentAllowance = _allowances[from][_msgSender()];
        require(currentAllowance >= rawAmount, "STKN: burn allowance exceeded");
        unchecked { _allowances[from][_msgSender()] -= rawAmount; }
        _burn(from, rawAmount);
    }

    // =========================================================================
    //  PAUSE / UNPAUSE — Emergency controls
    // =========================================================================

    /**
     * @notice Pause all token transfers. Emergency use only.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause token transfers after emergency is resolved.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // =========================================================================
    //  UTILITY VIEWS
    // =========================================================================

    /**
     * @notice Returns remaining mintable supply before hitting the hard cap.
     */
    function remainingMintable() external view returns (uint256) {
        return MAX_SUPPLY - _totalSupply;
    }

    /**
     * @notice Returns circulating supply (minted minus burned).
     */
    function circulatingSupply() external view returns (uint256) {
        return _totalSupply;
    }

    // =========================================================================
    //  INTERNAL HELPERS
    // =========================================================================

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "STKN: transfer from zero address");
        require(to != address(0), "STKN: transfer to zero address");
        require(_balances[from] >= amount, "STKN: insufficient balance");
        unchecked {
            _balances[from] -= amount;
            _balances[to]   += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "STKN: mint to zero address");
        _totalSupply     += amount;
        _balances[to]    += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        require(from != address(0), "STKN: burn from zero address");
        require(_balances[from] >= amount, "STKN: burn exceeds balance");
        unchecked {
            _balances[from] -= amount;
            _totalSupply    -= amount;
        }
        totalBurned += amount;
        emit Burn(from, amount);
        emit Transfer(from, address(0), amount);
    }

    // =========================================================================
    //  SAFETY — Reject accidental BNB sends
    // =========================================================================
    receive() external payable {
        revert("STKN: contract does not accept BNB");
    }
}

// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract Test is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isExcluded;
    mapping(address => bool) public _isBlackListed;

    mapping(address => uint256) public lastSellTime;
    mapping(address => uint8) public sellCount;

    address[] private _excluded;

    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal = 1 * 10**9 * 10**9;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 private _tFeeTotal;

    string private _name = "Test";
    string private _symbol = "TST";
    uint8 private _decimals = 9;

    struct Fee {
        uint16 marketingFee;
        uint16 burnFee;
        uint16 taxFee;
    }

    Fee public buyFee;
    Fee public sellFee;
    Fee public transferFee;

    Fee private fees;

    bool public isTradingEnabled;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    address public _marketingWallet = payable(address(0x123));

    bool private inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;
    uint256 public startTimestamp;

    uint256 public allTimeHigh;
    uint256 public priceImpactPercent;
    bool public isPriceImpactEnabled;
    uint256 public minimumBuy;

    uint256 public maxTxAmount;
    uint256 public maxWalletAmount;
    uint256 private numTokensSell;

    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    constructor() {
        _rOwned[_msgSender()] = _rTotal;

        buyFee.marketingFee = 90;
        buyFee.burnFee = 10;
        buyFee.taxFee = 50;

        sellFee.marketingFee = 90;
        sellFee.burnFee = 10;
        sellFee.taxFee = 50;

        transferFee.marketingFee = 80;
        transferFee.burnFee = 0;
        transferFee.taxFee = 0;

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3
        );
        // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        // set the rest of the contract variables
        uniswapV2Router = _uniswapV2Router;

        //exclude owner and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;

        maxWalletAmount = _tTotal.mul(2).div(100);
        maxTxAmount = _tTotal.mul(4).div(1000);
        priceImpactPercent = 7;
        isPriceImpactEnabled = true;
        minimumBuy = 0.02 ether;

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "ERC20: decreased allowance below zero"
            )
        );
        return true;
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function deliver(uint256 tAmount) public {
        address sender = _msgSender();
        require(
            !_isExcluded[sender],
            "Excluded addresses cannot call this function"
        );
        (uint256 rAmount, , , , ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rTotal = _rTotal.sub(rAmount);
        _tFeeTotal = _tFeeTotal.add(tAmount);
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee)
        public
        view
        returns (uint256)
    {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 rAmount, , , , ) = _getValues(tAmount);
            return rAmount;
        } else {
            (, uint256 rTransferAmount, , , ) = _getValues(tAmount);
            return rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount)
        public
        view
        returns (uint256)
    {
        require(
            rAmount <= _rTotal,
            "Amount must be less than total reflections"
        );
        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    function excludeFromReward(address account) public onlyOwner {
        // require(account != 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, 'We can not exclude Uniswap router.');
        require(!_isExcluded[account], "Account is already excluded");
        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeInReward(address account) external onlyOwner {
        require(_isExcluded[account], "Account is already excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function enableTrading() external onlyOwner {
        require(!isTradingEnabled, "Trading already enabled");
        startTimestamp = block.timestamp;
        isTradingEnabled = true;
    }

    function excludeFromFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function setBlackList(address addr, bool value) external onlyOwner {
        _isBlackListed[addr] = value;
    }

    function setPriceImpact(
        uint256 percent,
        uint256 minBuy,
        bool value
    ) external onlyOwner {
        priceImpactPercent = percent;
        isPriceImpactEnabled = value;
        minimumBuy = minBuy;
    }

    function includeInFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function setBuyFee(
        uint16 market,
        uint16 reward,
        uint16 tax
    ) external onlyOwner {
        buyFee.marketingFee = market;
        buyFee.burnFee = reward;
        buyFee.taxFee = tax;
    }

    function setSellFee(
        uint16 market,
        uint16 reward,
        uint16 tax
    ) external onlyOwner {
        sellFee.marketingFee = market;
        sellFee.burnFee = reward;
        sellFee.taxFee = tax;
    }

    function setTransferFee(
        uint16 market,
        uint16 reward,
        uint16 tax
    ) external onlyOwner {
        transferFee.marketingFee = market;
        transferFee.burnFee = reward;
        transferFee.taxFee = tax;
    }

    function setNumTokensSellToAddToLiquidity(uint256 numTokens)
        external
        onlyOwner
    {
        numTokensSell = numTokens;
    }

    function updateRouter(address newAddress) external onlyOwner {
        require(
            newAddress != address(uniswapV2Router),
            "TOKEN: The router already has that address"
        );
        uniswapV2Router = IUniswapV2Router02(newAddress);
        address _uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Pair = _uniswapV2Pair;
    }

    function setMaxTx(uint256 maxTx) external onlyOwner {
        maxTxAmount = maxTx;
    }

    function setMaxWallet(uint256 _maxWalletAmount) external onlyOwner {
        maxWalletAmount = _maxWalletAmount;
    }

    function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }

    function claimStuckTokens(address _token) external onlyOwner {
        require(_token != address(this), "No rug pulls :)");

        if (_token == address(0x0)) {
            payable(owner()).transfer(address(this).balance);
            return;
        }

        IERC20 erc20token = IERC20(_token);
        uint256 balance = erc20token.balanceOf(address(this));
        erc20token.transfer(owner(), balance);
    }

    //to recieve ETH from uniswapV2Router when swaping
    receive() external payable {}

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _getValues(uint256 tAmount)
        private
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        (
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tBurn,
            uint256 tMarketing
        ) = _getTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(
            tAmount,
            tFee,
            tBurn,
            tMarketing,
            _getRate()
        );
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee);
    }

    function _getTValues(uint256 tAmount)
        private
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 tFee = calculateTaxFee(tAmount);
        uint256 tBurn = calculateBurnFee(tAmount);
        uint256 tMarketing = calculateMarketingFee(tAmount);
        uint256 tTransferAmount = tAmount.sub(tFee);
        tTransferAmount = tTransferAmount.sub(tBurn).sub(tMarketing);
        return (tTransferAmount, tFee, tBurn, tMarketing);
    }

    function _getRValues(
        uint256 tAmount,
        uint256 tFee,
        uint256 tBurn,
        uint256 tMarketing,
        uint256 currentRate
    )
        private
        pure
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rBurn = tBurn.mul(currentRate);
        uint256 rMarketing = tMarketing.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rBurn).sub(rMarketing);
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (
                _rOwned[_excluded[i]] > rSupply ||
                _tOwned[_excluded[i]] > tSupply
            ) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function _takeBurn(address sender, uint256 tBurn) private {
        uint256 currentRate = _getRate();
        uint256 rBurn = tBurn.mul(currentRate);
        _rOwned[address(0xdead)] = _rOwned[address(0xdead)].add(rBurn);
        if (_isExcluded[address(0xdead)]) {
            _tOwned[address(0xdead)] = _tOwned[address(0xdead)].add(tBurn);
        }

        if (tBurn > 0) {
            emit Transfer(sender, address(0xdead), tBurn);
        }
    }

    function _takeMarketing(
        address sender,
        address recipient,
        uint256 tMarketing
    ) private {
        uint256 currentRate = _getRate();
        uint256 rMarketing = tMarketing.mul(currentRate);

        if (sender != uniswapV2Pair && recipient != uniswapV2Pair) {
            if (tMarketing > 0) {
                _rOwned[_marketingWallet] = _rOwned[_marketingWallet].add(
                    rMarketing
                );
                if (_isExcluded[_marketingWallet]) {
                    _tOwned[_marketingWallet] = _tOwned[_marketingWallet].add(
                        tMarketing
                    );
                }

                emit Transfer(sender, _marketingWallet, tMarketing);
            }
        } else {
            _rOwned[address(this)] = _rOwned[address(this)].add(rMarketing);
            if (_isExcluded[address(this)])
                _tOwned[address(this)] = _tOwned[address(this)].add(tMarketing);
        }
    }

    function calculateTaxFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(fees.taxFee).div(10**3);
    }

    function calculateBurnFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(fees.burnFee).div(10**3);
    }

    function calculateMarketingFee(uint256 _amount)
        private
        view
        returns (uint256)
    {
        return _amount.mul(fees.marketingFee).div(10**3);
    }

    function removeAllFee() private {
        fees.taxFee = 0;
        fees.burnFee = 0;
        fees.marketingFee = 0;
    }

    function setFees(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        if (sender != uniswapV2Pair && recipient != uniswapV2Pair) {
            fees = transferFee;
        } else {
            uint256 price = getPriceOfToken(1 * 10**9);
            if (price >= allTimeHigh) {
                allTimeHigh = price;
            }

            if (sender == uniswapV2Pair) {
                price = getPriceOfToken(amount);
                require(price >= minimumBuy, "Min buy not met");
                fees = buyFee;
                return;
            }
            if (recipient == uniswapV2Pair) {
                if (isPriceImpactEnabled) {
                    require(
                        price >=
                            allTimeHigh.mul(100 - priceImpactPercent).div(100),
                        "Price impact too high"
                    );
                }
                if (block.timestamp >= startTimestamp + 72 hours) {
                    fees = sellFee;
                } else {
                    if (block.timestamp >= lastSellTime[sender] + 24 hours) {
                        sellCount[sender] = 0;
                    }
                    fees.taxFee = 50;
                    fees.burnFee = 10;
                    if (sellCount[sender] == 0) {
                        require(
                            block.timestamp >= lastSellTime[sender] + 1 hours,
                            "Cooldown enabled"
                        );
                        fees.marketingFee = 200;
                    } else if (sellCount[sender] == 1) {
                        require(
                            block.timestamp >= lastSellTime[sender] + 2 hours,
                            "Cooldown enabled"
                        );
                        fees.marketingFee = 220;
                    } else if (sellCount[sender] == 2) {
                        require(
                            block.timestamp >= lastSellTime[sender] + 6 hours,
                            "Cooldown enabled"
                        );
                        fees.marketingFee = 250;
                    } else {
                        require(
                            block.timestamp >= lastSellTime[sender] + 12 hours,
                            "Cooldown enabled"
                        );
                        fees.marketingFee = 260;
                    }

                    lastSellTime[sender] = block.timestamp;
                    sellCount[sender]++;
                }
            }
        }
    }

    function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function getPriceOfToken(uint256 amount)
        public
        view
        returns (uint256 price)
    {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        price = (uniswapV2Router.getAmountsOut(amount, path))[path.length - 1];
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        if (from != owner() && to != owner()) {
            require(
                amount <= maxTxAmount,
                "Transfer amount exceeds the maxTxAmount."
            );

            require(isTradingEnabled, "Trading not enabled yet");

            if (to != uniswapV2Pair) {
                require(
                    balanceOf(to) + amount <= maxWalletAmount,
                    "Transfer exceeds max wallet"
                );
            }
        }

        require(
            !_isBlackListed[from] && !_isBlackListed[to],
            "Account is blacklisted"
        );

        // is the token balance of this contract address over the min number of
        // tokens that we need to initiate a swap + liquidity lock?
        // also, don't get caught in a circular liquidity event.
        // also, don't swap & liquify if sender is uniswap pair.
        uint256 contractTokenBalance = balanceOf(address(this));

        if (contractTokenBalance >= maxTxAmount) {
            contractTokenBalance = maxTxAmount;
        }

        bool overMinTokenBalance = contractTokenBalance >= numTokensSell;
        if (
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            from != uniswapV2Pair &&
            swapAndLiquifyEnabled
        ) {
            contractTokenBalance = numTokensSell;
            swapAndSendFee(contractTokenBalance);
        }

        //indicates if fee should be deducted from transfer
        bool takeFee = true;

        //if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            takeFee = false;
        }

        //transfer amount, it will take tax, reward, liquidity fee
        _tokenTransfer(from, to, amount, takeFee);
    }

    function swapAndSendFee(uint256 amount) private lockTheSwap {
        uint256 initialBalance = address(this).balance;
        swapTokensForEth(amount);
        uint256 newBalance = address(this).balance.sub(initialBalance);

        payable(_marketingWallet).transfer(newBalance);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        bool takeFee
    ) private {
        removeAllFee();

        if (takeFee) {
            setFees(sender, recipient, amount);
        }

        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }
    }

    function _transferStandard(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee
        ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeBurn(sender, calculateBurnFee(tAmount));
        _takeMarketing(sender, recipient, calculateMarketingFee(tAmount));
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferToExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee
        ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeBurn(sender, calculateBurnFee(tAmount));
        _takeMarketing(sender, recipient, calculateMarketingFee(tAmount));
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferFromExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee
        ) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeBurn(sender, calculateBurnFee(tAmount));
        _takeMarketing(sender, recipient, calculateMarketingFee(tAmount));
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferBothExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee
        ) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeBurn(sender, calculateBurnFee(tAmount));
        _takeMarketing(sender, recipient, calculateMarketingFee(tAmount));
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }
}

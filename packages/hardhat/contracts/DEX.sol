// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title DEX Template
 * @author stevepham.eth and m00npapi.eth
 * @notice Empty DEX.sol that just outlines what features could be part of the challenge (up to you!)
 * @dev We want to create an automatic market where our contract will hold reserves of both ETH and 🎈 Balloons. These reserves will provide liquidity that allows anyone to swap between the assets.
 * NOTE: functions outlined here are what work with the front end of this branch/repo. Also return variable names that may need to be specified exactly may be referenced (if you are confused, see solutions folder in this repo and/or cross reference with front-end code).
 */
contract DEX {
    /* ========== GLOBAL VARIABLES ========== */

    using SafeMath for uint256; //outlines use of SafeMath for uint256 variables
    IERC20 token; //instantiates the imported contract

    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidity;
    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when ethToToken() swap transacted
     */
    event EthToTokenSwap();

    /**
     * @notice Emitted when tokenToEth() swap transacted
     */
    event TokenToEthSwap();

    /**
     * @notice Emitted when liquidity provided to DEX and mints LPTs.
     */
    event LiquidityProvided();

    /**
     * @notice Emitted when liquidity removed from DEX and decreases LPT count within DEX.
     */
    event LiquidityRemoved();

    /* ========== CONSTRUCTOR ========== */

    constructor(address token_addr) public {
        token = IERC20(token_addr); //specifies the token address that will hook into the interface and be used through the variable 'token'
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice initializes amount of tokens that will be transferred to the DEX itself from the erc20 contract mintee (and only them based on how Balloons.sol is written). Loads contract up with both ETH and Balloons.
     * @param tokens amount to be transferred to DEX
     * @return totalLiquidity is the number of LPTs minting as a result of deposits made to DEX contract
     * NOTE: since ratio is 1:1, this is fine to initialize the totalLiquidity (wrt to balloons) as equal to eth balance of contract.
     */
    function init(uint256 tokens) public payable returns (uint256) {
        require(totalLiquidity == 0, "DEX: init - already has liquidity");
        // total liquidity is this contract's current eth balance
        totalLiquidity = address(this).balance;
        // assign the equivalent of this contract's eth balance
        // as the $BAL balance of the sender
        liquidity[msg.sender] = totalLiquidity;
        require(
            token.transferFrom(msg.sender, address(this), tokens),
            "DEX: init - transfer did not transact"
        );
        return totalLiquidity;
    }

    /**
     * @notice returns yOutput, or yDelta for xInput (or xDelta)
     * @dev Follow along with the [original tutorial](https://medium.com/@austin_48503/%EF%B8%8F-minimum-viable-exchange-d84f30bd0c90) Price section for an understanding of the DEX's pricing model and for a price function to add to your contract. You may need to update the Solidity syntax (e.g. use + instead of .add, * instead of .mul, etc). Deploy when you are done.
     */
    function price(
        uint256 xInput,
        uint256 xReserves,
        uint256 yReserves
    ) public view returns (uint256 yOutput) {
        uint256 xInputWithFee = xInput.mul(997);
        uint256 numerator = xInputWithFee.mul(yReserves);
        uint256 denominator = (xReserves.mul(1000)).add(xInputWithFee);
        return (numerator / denominator);
    }

    /**
     * @notice sends Ether to DEX in exchange for $BAL
     */
    function ethToToken() public payable returns (uint256 tokenOutput) {
        require(msg.value > 0, "Cannot swap 0 ETH");
        // get tokenReserves, ethReserves
        uint256 tokenReserves = token.balanceOf(address(this));
        uint256 ethReserves = address(this).balance;
        // get tokenOutput price based on ethInput, ethReserves, tokenReserves
        uint256 tokenOutput = price(msg.value, ethReserves, tokenReserves);
        // this shouldn't need to be called
        // require(
        //     tokenReserves > tokenOutput,
        //     "Not enough tokenReserves available."
        // );
        // transfer $BAL tokens to the sender
        require(
            token.transfer(msg.sender, tokenOutput),
            "token transfer unsuccessful"
        );

        // return tokenOutput
        return tokenOutput;
    }

    /**
     * @notice sends $BAL tokens to DEX in exchange for Ether
     */
    function tokenToEth(uint256 tokenInput) public returns (uint256 ethOutput) {
        // get tokenReserves, ethReserves
        uint256 tokenReserves = token.balanceOf(address(this));
        uint256 ethReserves = address(this).balance;
        // get ethOutput price based on tokenInput, ethReserves, tokenReserves
        ethOutput = price(tokenInput, tokenReserves, ethReserves);
        // transfer token balance from sender to DEX
        // transferFrom method returns bool indicating whether operation succeeded
        // https://docs.openzeppelin.com/contracts/2.x/api/token/erc20#IERC20-transferFrom-address-address-uint256-
        require(
            token.transferFrom(msg.sender, address(this), tokenInput),
            "token transfer unsuccessful"
        );
        // pay ETH to sender
        // using call() instead of send() or transfer()
        // https://consensys.github.io/smart-contract-best-practices/development-recommendations/general/external-calls/
        (bool success, ) = msg.sender.call{value: ethOutput}("");
        require(success, "eth not sent to sender");
        return ethOutput;
    }

    /**
     * @notice allows deposits of $BAL and $ETH to liquidity pool
     * NOTE: parameter is the msg.value sent with this function call. That amount is used to determine the amount of $BAL needed as well and taken from the depositor.
     * NOTE: user has to make sure to give DEX approval to spend their tokens on their behalf by calling approve function prior to this function call.
     * NOTE: Equal parts of both assets will be removed from the user's wallet with respect to the price outlined by the AMM.
     */
    function deposit() public payable returns (uint256 tokensDeposited) {
        // assuming I want each deposit to maintain the pre-existing ratio of BAL : ETH,
        // even if it F's up k
        require(msg.value > 0, "cannot deposit zero tokens");
        uint256 ethReserve = address(this).balance.sub(msg.value);
        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 tokenDeposit;

        tokenDeposit = msg.value.mul(tokenReserve) / ethReserve;
        // because of fees, liquidity might not be the same as reserves (liquidity should be lower)
        uint256 liquidityMinted = msg.value.mul(totalLiquidity) / ethReserve;

        liquidity[msg.sender] = liquidity[msg.sender].add(liquidityMinted);
        totalLiquidity = totalLiquidity.add(liquidityMinted);
        require(
            token.transferFrom(msg.sender, address(this), tokenDeposit),
            "token transfer from sender unsuccessful"
        );
        return tokenDeposit;
    }

    /**
     * @notice allows withdrawal of $BAL and $ETH from liquidity pool
     * NOTE: with this current code, the msg caller could end up getting very little back if the liquidity is super low in the pool. I guess they could see that with the UI.
     */
    function withdraw(uint256 amount)
        public
        returns (uint256 eth_amount, uint256 token_amount)
    {
        // ensure the amount requested is not greater than the amount they've put in
        // calculate the amount of ETH to send them based on the token amount requested and the eth reserves
        // adjust liquidity[msg.sender] and totalLiquidity
        // transfer tokens, send eth via call
        require(
            liquidity[msg.sender] >= amount,
            "can only take out of the DEX something LTE than what you put in!"
        );

        uint256 ethReserve = address(this).balance;
        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 ethWithdrawal;

        // use totalLiquidity b/c that excludes fees accrued by DEX and also
        ethWithdrawal = amount.mul(ethReserve) / totalLiquidity;
        // calculate the tokenAmount (which should be bigger than the amount) b/c it includes accrued fees
        uint256 tokenAmount = amount.mul(tokenReserve) / totalLiquidity;
        require(
            address(this).balance > ethWithdrawal,
            "not enough ETH in DEX to make withdrawal"
        );

        liquidity[msg.sender] = liquidity[msg.sender] - amount;
        totalLiquidity = totalLiquidity - amount;
        require(token.transfer(msg.sender, tokenAmount));

        (bool success, ) = payable(msg.sender).call{value: ethWithdrawal}("");
        require(success);
        return (ethWithdrawal, tokenAmount);
    }
}

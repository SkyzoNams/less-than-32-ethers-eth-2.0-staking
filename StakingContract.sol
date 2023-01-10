// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "./IDepositContract.sol";
import {StakingContractLibrary as lib} from "./StakingContractLibrary.sol";

//*************************Interface*************************//
interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function decimals() external view returns (uint8);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);
}

interface StakingContractDepositAndClaiming {
    function deposit() external payable;

    function claim(address _claimer) external;
}

/**
 * @title
 * @authors
 */
contract StakingContract is IERC20 {
    //*************************Global variables*************************//
    //@dev Time datastores
    //The start time of each investment
    uint256 public investmentStartTime;

    /**
     * @dev Function is used to reset the timer for the investment start time
     */
    function setInvestmentTimer() internal {
        investmentStartTime = block.timestamp;
    }

    //The APR% returns the user gets after each inestment period
    uint32 public annualInterestRate;
    //How many investment phases have passes
    uint16 public investmentPhase = 1;

    //The amount of days the deposit period has
    uint8 public depositExpirationDays;
    //The number of days the investment is
    uint32 public lockedPeriod;
    //The number of days the users have to claim their reward Eth
    uint256 public claimPeriod;

    //True if the node has colapsed
    bool public hasNodeColapsed;

    //The address to give excess Eth on this contract
    address public skimAddress;

    /**
     * @notice Current status of investment
     * @dev     enum Status {
                    Depositing,
                    Ready_To_Invest,
                    Investing,
                    Claiming,
                    Withdrawing,
                    Refunding,
                    Expired
                }
     */
    lib.Status public status;

    /**
     * @dev Contract mappings
     */
    mapping(address => uint256) internal balances;
    mapping(address => mapping(address => uint256)) internal allowed;
    mapping(uint16 => mapping(address => bool)) public claimedRewards;
    mapping(address => lib.SellStruct) public toSell;

    /**
     * @dev contract events
     */
    event offered(
        address seller,
        lib.SellStruct _swapInfo,
        address _contractAddress
    );
    event sold(
        address seller,
        address buyer,
        lib.SellStruct _swapInfo,
        address _contractAddress,
        uint256 _sellerBalance,
        uint256 _buyerBalance
    );
    event Transfer(address from, address to, uint256 value);
    event approval(address owner, address spender, uint256 value);
    event readyToInvest(address _contractAddress, uint256 _lockedPeriodInDays);
    event transferEth(address _userAddress, uint256 _amount, address _contract);
    event fundsReceived(
        address sender,
        uint256 amount,
        address _contractAddress
    );
    event userDeposit(
        uint256 _depositAmount,
        address _userAddress,
        address _contractAddress,
        uint256 _userBalance
    );
    event sentRewards(
        address _user,
        uint256 _claimedAmount,
        address _contractAddress,
        uint256 _userBalance,
        uint256 _time
    );
    event tokenSwapedForEth(
        address _userAddress,
        uint256 _amount,
        address _contractAddress,
        uint256 _userBalance,
        uint256 _time
    );
    event ethersSentToTheStakingContract(
        uint256 _amount,
        address _contractAddress,
        uint256 _investingStartTime,
        string _pubkey
    );
    event stakingInstanceCreated(
        address _contractAddress,
        uint256 _lockedPeriodInDays,
        uint256 _annualRate,
        uint256 _depositExpirationDays,
        uint256 _time
    );
    event StatusSwitched(lib.Status _newStatus, address _contractAddress);

    /**
     * @dev Stops certain funtions if needed for the status
     */
    bool public depositAllowed;
    bool public tradingAllowed;
    bool public withdrawAllowed;
    bool public claimAllowed;

    enum pausers {
        depositing,
        trading,
        withdrawing,
        claiming
    }

    //*************************Modifiers*************************//
    /**
     * @dev     Modifier does not allow the function to work if the pauser if false
     * @param   _item The item to look look for in the pausers Enum
     */
    modifier pauseFor(pausers _item) {
        require(isAllowed(_item), "Pauser: Function cannot be used right now");
        _;
    }

    /**
     * @dev     Checks if a item is paused
     * @param   _item The item to look look for in the pausers Enum
     * @return  bool True if the item is able to be used
     */
    function isAllowed(pausers _item) public view returns (bool) {
        if (_item == pausers.depositing) return depositAllowed;
        if (_item == pausers.trading) return tradingAllowed;
        if (_item == pausers.withdrawing) return withdrawAllowed;
        if (_item == pausers.claiming) return claimAllowed;
        return false;
    }

    /**
     * @dev     Toggles the function pausers on or off
     * @dev     Only used by the switcher function
     * @param   _item The item to look look for in the pausers Enum
     * @param   _toggle Bool to change item to
     */
    function allowPause(pausers _item, bool _toggle) internal {
        if (_item == pausers.depositing) depositAllowed = _toggle;
        if (_item == pausers.trading) tradingAllowed = _toggle;
        if (_item == pausers.withdrawing) withdrawAllowed = _toggle;
        if (_item == pausers.claiming) claimAllowed = _toggle;
    }

    /**
     * @dev Standard reentrancy lock
     */
    bool internal lock;
    modifier reentrancyProtected() {
        require(lock == false, "Reentrancy: Reentrancy detected");
        lock = true;
        _;
        lock = false;
    }

    /**
     * @dev Owner controls are used but only for recovery and sending of the funds to the Eth 2.0 contract
     */
    address owner;
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    //*************************Constructor*************************//

    /**
     * @dev Contract and doken setup
     *
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimal,
        uint32 _lockedPeriod,
        uint32 _annualInterestRate,
        uint8 _depositExpirationDays,
        uint8 _claimPeriod,
        address _skimAddress
    ) {
        //ERC20
        Name = _name;
        Symbol = _symbol;
        Decimals = _decimal;

        //Time
        lockedPeriod = _lockedPeriod;
        claimPeriod = _claimPeriod;
        depositExpirationDays = _depositExpirationDays;

        annualInterestRate = _annualInterestRate;

        //State setup
        lock = false;
        skimAddress = _skimAddress;

        owner = msg.sender;

        //Record the start time and allow trading and depositing
        //We use the investment timer here to save space on not having another timer
        setInvestmentTimer();
        allowPause(pausers.trading, true);
        allowPause(pausers.depositing, true);

        //Emit event
        emit stakingInstanceCreated(
            address(this),
            lockedPeriod,
            annualInterestRate,
            depositExpirationDays,
            block.timestamp
        );
    }

    //*************************Status switching*************************//
    /**
     * @dev     This switches the current status of the investment on the contract
                Called like this
                switchStatus( lib.Status(x));
                Checks are done at this stage if the status is switchable
                There may be redundancies in the switching checks
        @param  _passStatus The status that the contract will switch to
        @notice Emits the status switched event
     */
    function switchStatus(lib.Status _passStatus) internal {
        if (_passStatus == lib.Status.Depositing) {
            //Depositing
            //Only switch to this on deployment
            status = lib.Status.Depositing;
            //Record the start time and allow trading and depositing
            //We use the investment timer here to save space on not having another timer
            setInvestmentTimer();
            allowPause(pausers.trading, true);
            allowPause(pausers.depositing, true);
        } else if (_passStatus == lib.Status(1)) {
            //Ready To invest
            //Only switch to this status if the contrac tis currently depositing
            //Must have 32 Eth after the skim to switch to this status
            skimEth();
            require(
                address(this).balance == 32 ether,
                "Switching: not enought Eth"
            );
            require(
                isStatus(lib.Status.Depositing),
                "Switching: Current status invalid to switch to Depositing"
            );
            status = lib.Status.Ready_To_Invest;

            //Contract sends an Event to show that investment is ready
            emit readyToInvest(address(this), lockedPeriod);

            //Modifier toggles only deposit. It assumes trading is true and claiming is false
            allowPause(pausers.depositing, false);
        } else if (_passStatus == lib.Status(2)) {
            //Invested

            //Change the investment start to the current time
            //Only does this if it is switching from ready to invest
            //Claiming will change the timestamp in it's switch
            if (isStatus(lib.Status.Ready_To_Invest)) setInvestmentTimer();

            //Adds one to the number of investment phases that this contract has
            investmentPhase += 1;

            status = lib.Status.Investing;

            //Modifier toggles
            //This assumes deposit is already false
            //Resets the functions from the claiming statuss
            allowPause(pausers.trading, true);
            allowPause(pausers.claiming, false);
        } else if (_passStatus == lib.Status(3)) {
            //Claiming
            //Allows the user to claim their token rewards
            status = lib.Status.Claiming;

            //Change the time for the next investment here
            setInvestmentTimer();

            //Modifier toggles
            allowPause(pausers.trading, false);
            allowPause(pausers.claiming, true);
        } else if (_passStatus == lib.Status(4)) {
            //Withdrawing
            //Allows users to claim their final reward and then withdraw
            require(
                address(this).balance >= 32 ether,
                "Switching: not enought Eth"
            );
            require(
                hasNodeColapsed == true,
                "Switching: Node has not colapsed yet"
            );

            //Both claiming and withdrawing are allowed
            //Stop all trading from now
            status = lib.Status.Withdrawing;
            allowPause(pausers.trading, false);
            allowPause(pausers.claiming, true);
            allowPause(pausers.withdrawing, true);
        } else if (_passStatus == lib.Status(5)) {
            //Refunding
            //Allows for just withdrawals
            require(
                isStatus(lib.Status.Depositing),
                "Switching: Current status invalid to switch to Refunding"
            );
            status = lib.Status.Refunding;

            //Stop anymore deposits and allow users to refund their Eth
            allowPause(pausers.withdrawing, true);
            allowPause(pausers.depositing, false);
        } else if (_passStatus == lib.Status(6)) {
            //Expired
            status = lib.Status.Expired;
            allowPause(pausers.trading, false);
            allowPause(pausers.withdrawing, true);
        }
        emit StatusSwitched(_passStatus, address(this));
    }

    /**
     * @dev     Checks if the contract is at the current passed status
                isStatus( lib.Status(x));
                isStatus( lib.Status.{status});
        @param  _passStatus The status to match
        @return bool True if the status matches the contract status
                False if they do not match
     */
    function isStatus(lib.Status _passStatus) public view returns (bool) {
        return _passStatus == status;
    }

    //*************************ERC20 standard Functions*************************//
    //All event handlers are done in the internal functions in the ERC20 functions
    //There are two that happen one when tokens are transfered
    //The second is when an approval changes

    /**
     * @dev Token datastores
     */
    string internal Name;
    string internal Symbol;
    uint8 internal Decimals;
    uint256 internal TotalSupply;

    /**
     * @dev     Standard ERC20 functions
     * @notice  Theese are the getter functions for the ERC20 data
     */
    function totalSupply() public view virtual override returns (uint256) {
        return TotalSupply;
    }

    function decimals() public view virtual override returns (uint8) {
        return Decimals;
    }

    function name() public view virtual override returns (string memory) {
        return Name;
    }

    function symbol() public view virtual override returns (string memory) {
        return Symbol;
    }

    function balanceOf(address _owner) public view override returns (uint256) {
        return balances[_owner];
    }

    /**
     * @dev    Standard ERC20 function
     * @notice Transfers tokens from the senders address to the _delegate address
     * @param  _delegate The reciver of the token
     * @param  _value The amount to send
     */
    function transfer(address _delegate, uint256 _value)
        public
        override
        reentrancyProtected
        pauseFor(pausers.trading)
        returns (bool)
    {
        require(
            _value <= balances[msg.sender],
            "ERC20: Not enough Eth to transfer"
        );
        moveTokens(msg.sender, _delegate, _value);
        return true;
    }

    /**
     * @dev     Standard ERC20 function
     * @param  _delegate The reciver of the allowance
     * @param  _value The amount to approve
     */
    function approve(address _delegate, uint256 _value)
        public
        override
        returns (bool)
    {
        changeTokenAllowance(msg.sender, _delegate, _value);
        return true;
    }

    /**
     * @dev     Standard ERC20 function
     * @param  _owner The owner of the tokens
     * @param  _delegate The reciver of the allowance
     */
    function allowance(address _owner, address _delegate)
        public
        view
        override
        returns (uint256)
    {
        return allowed[_owner][_delegate];
    }

    /**
     * @dev     Standard ERC20 function
     * @param  _owner The owner of the tokens
     * @param  _delegate The reciver of the allowance
     * @param  _value The amount of tokens to send
     */
    function transferFrom(
        address _owner,
        address _delegate,
        uint256 _value
    )
        public
        override
        reentrancyProtected
        pauseFor(pausers.trading)
        returns (bool)
    {
        require(_value <= balances[_owner], "ERC20: Not enough tokens to sent");
        require(
            _value <= allowed[_owner][msg.sender],
            "ERC20: Over the allowed limit of tokens"
        );
        spendAllowance(_owner, msg.sender, _value);
        moveTokens(_owner, _delegate, _value);
        return true;
    }

    /**
     * @notice  Moves tokens from one address to another
     *          Emits the transfer event when it does
     * @dev     This is used as a helper function to move tokens
     *          The only check that is done here is that the user has enough tokens
                And the transfer is not to the 0 address
                Used by transfer and transfer from
     * @param  _owner The owner of the tokens
     * @param  _delegate The reciver of the allowance
     * @param  _value The amount of tokens to send
     */
    function moveTokens(
        address _owner,
        address _delegate,
        uint256 _value
    ) internal virtual {
        uint256 fromBalance = balances[_owner];
        require(
            _owner != address(0) && _delegate != address(0),
            "ERC20: Cannot use the 0 address"
        );
        require(fromBalance >= _value, "ERC20: Not enough tokens to transfer");

        balances[_owner] -= _value;
        balances[_delegate] += _value;
        emit Transfer(_owner, _delegate, _value);
    }

    /**
     * @dev     Updates an allowance as if it were spend
     *          Does not check here if there are the tokens to send
     *          This just reduces the balance of the allowance
     * @dev     Used whenever an allowance is spent
     *          Not necissaraly just in the ERC20 functions
     * @param   _owner The owner of the tokens
     * @param   _delegate The reciver of the allowance
     * @param   _value The amount to reduce the allowance by
     */
    function spendAllowance(
        address _owner,
        address _delegate,
        uint256 _value
    ) internal virtual {
        uint256 currentAllowance = allowance(_owner, _delegate);
        if (currentAllowance != type(uint256).max) {
            require(
                currentAllowance >= _value,
                "ERC20: insufficient allowance"
            );
            unchecked {
                changeTokenAllowance(
                    _owner,
                    _delegate,
                    currentAllowance - _value
                );
            }
        }
    }

    /**
     * @dev     Sets the amount in an allowance
     *          Emits the approval event
     * @notice  This sets the amount equal to the passed in amount#
     * @param   _owner The owner of the tokens
     * @param   _delegate The reciver of the allowance
     * @param   _value The amount to set the allowance to
     */
    function changeTokenAllowance(
        address _owner,
        address _delegate,
        uint256 _value
    ) internal virtual {
        require(
            _owner != address(0) && _delegate != address(0),
            "ERC20: Cannot use the 0 address"
        );
        allowed[_owner][_delegate] = _value;
        emit approval(_owner, _delegate, _value);
    }

    /**
     * @notice  This function will mint x tokens to a user's wallet
     * @dev     The tokens are minted to the users account
                The transfer event will transfer the tokens from address 0
     * @dev     This funciton is unchecked please do all the checks before minting
     * @param   _owner The owner address
     * @param   _value The amount to mint
     */
    function mint(address _owner, uint256 _value) internal {
        unchecked {
            balances[_owner] += _value;
            TotalSupply += _value;
        }
        emit Transfer(address(0), _owner, _value);
    }

    /**
     * @notice  This function will burn x tokens from a user's wallet
     * @dev     This event will show as transfering the tokens to address 0
     * @param   _owner The owner address
     * @param   _value The amount to burn
     */
    function burn(address _owner, uint256 _value)
        internal
        pauseFor(pausers.withdrawing)
    {
        require(
            balanceOf(_owner) >= _value,
            "ERC20: Not enought tokens to burn"
        );
        unchecked {
            balances[_owner] -= _value;
            TotalSupply -= _value;
        }

        //If there are no more tokens then expire the contract
        if (totalSupply() == 0) switchStatus(lib.Status.Expired);
        emit Transfer(_owner, address(0), _value);
    }

    //*************************Deposit period*************************//
    /**
     * @dev     This function will give user's tokens depoending on how much Eth they have sent
     * @notice  The deposits will be recorded under the address of the message sender
                The tokens are minted directly to the sender
     */
    function deposit()
        public
        payable
        reentrancyProtected
        pauseFor(pausers.depositing)
    {
        //Checks if the deposit is valid
        require(
            (msg.value > 0) &&
                (msg.value % 0.1 ether == 0) &&
                (address(this).balance) <= 32 ether,
            "Deposit: Invalid deposit amount"
        );

        require(isDepositPeriod(), "Deposit: Invalid time");

        //It mints the tokens to the user and emits an event
        mint(msg.sender, msg.value);

        //If there is any excess Eth that shouldn't be on the contract then send it away
        skimEth();

        emit userDeposit(
            msg.value,
            msg.sender,
            address(this),
            balances[msg.sender]
        );

        //Then if there are 32 Ethers on the contract its ready to go
        if (address(this).balance == 32 ether) {
            switchStatus(lib.Status.Ready_To_Invest);
        }
    }

    /**
     * @notice  Takes the excess Eth of the contract
     * @dev     Cannot take out more than the amount of tokens on the contract
     * @dev     Gets the total supply of the contract
                This will show how much wei must be on the contract
                Then if the amount on the contract is higher than the expected amount
                Send the excess off to the skimmer address
     */
    function skimEth() public virtual {
        uint256 contractBalance = address(this).balance;
        if (contractBalance > totalSupply())
            sendEth(skimAddress, contractBalance - totalSupply());
    }

    //*************************Buy and sell functions*************************//
    /**
     * @notice  User's offer their tokens for an Eth price
     * @dev     function isn't transfer protected but buying the offer is
     * @param   _amount The amount of tokens the user wants to sell
     * @param   _price The amount of Eth in Wei that the user wants theese tokens for
     */
    function offerTokens(uint256 _amount, uint256 _price) public {
        //Check the user's token amount first
        require(
            balanceOf(msg.sender) >= _amount,
            "Auction: Not enough tokens to send"
        );

        //Allow this contract to take the Eth on purchase
        //Then save the details
        approve(address(this), _amount);
        lib.SellStruct memory offerDetails = lib.SellStruct(_amount, _price);
        toSell[msg.sender] = offerDetails;
        emit offered(msg.sender, offerDetails, address(this));
    }

    /**
     * @dev     Function is transfered protected
     * @dev     Use this function to buy a token offer
     * @param   _seller The address of the seller that is selling the tokens
     * @notice  Function will revert if the seller has no token offer
                Will also revert is the user pays the wrong price
     */
    function buyUserOffer(address _seller) public payable {
        //Get the offer from storage and then check if:
        //Tokens are being offered
        //The user has sent the right amount
        lib.SellStruct memory offerDetails = toSell[_seller];
        require(
            offerDetails.amount > 0,
            "Auction: No tokens are being offered"
        );
        require(msg.value == offerDetails.price, "Auction: Wrong amount paid");

        //Clear the user's offer
        toSell[_seller] = lib.SellStruct(0, 0);

        //Then get move the tokens from the seller to the buyer
        spendAllowance(_seller, address(this), offerDetails.amount);
        moveTokens(_seller, msg.sender, offerDetails.amount);

        //Then pay the seller and emit the recipt
        sendEth(_seller, offerDetails.price);
        emit sold(
            _seller,
            msg.sender,
            offerDetails,
            address(this),
            balances[_seller],
            balances[msg.sender]
        );
    }

    //*************************Withdrawal controls*************************//
    /**
     * @dev     Main function for both getting reward tokens and withdrawing Eth
     * @dev     On external apps only use this one function for user claims
     * @notice  This function changes depending on the status of the contract
                This will also change the status of the contract if needed
     * @param   _claimer The address that is being claimed for
     */
    function claim(address _claimer) public reentrancyProtected {
        manageClaimPeriod();
        if (isStatus(lib.Status.Claiming)) {
            //If the user can only get their token rewards
            giveTokenRewards(_claimer);
        } else if (isStatus(lib.Status.Withdrawing)) {
            //If a user can claim a token reward and get a refund
            giveTokenRewards(_claimer);
            withdraw(_claimer);
        } else if (isStatus(lib.Status.Refunding)) {
            //If the user can only get a refund
            withdraw(_claimer);
        } else {
            //If the contract does not have any of the statuses revert
            //This is to protect in case of problems of using manage claim period
            revert();
        }
    }

    /**
     * @dev     This function manages the investment and claim period
     * @dev     This can also be called directly to unstick any problems with updating the status
     * @notice  This will change the status to the claim period if the investment has finished
                It will also change the claim period back to the investment period if possible
                If the node has colapsed and the investment has finished then allow for withdrawing
     */
    function manageClaimPeriod() public returns (bool) {
        if (hasNodeColapsed == true && !isStatus(lib.Status.Withdrawing)) {
            //If the node has colapsed do this and only this
            //First check if the investment has finished then set the status to withdraw
            require(
                !isInvestmentPeriod(),
                "Claim: Investment has not finished yet"
            );
            switchStatus(lib.Status.Withdrawing);
            return true;
        }

        //If the node hasn't colapsed yet check what period it is and if a user can claim
        if (isStatus(lib.Status.Investing)) {
            //If it is in the investment period then check if the investment period has finished
            require(
                !isInvestmentPeriod(),
                "Claim: Investment has not finished yet"
            );
            switchStatus(lib.Status.Claiming);
            return true;
        } else if (isStatus(lib.Status.Claiming) && !isClaimPeriod()) {
            //If the status is on claiming and the claim has finished then switch to investing
            switchStatus(lib.Status.Investing);
            return true;
        } else if (
            isStatus(lib.Status.Depositing) &&
            lib.elapsedTimeSince(investmentStartTime) >= depositExpirationDays
        ) {
            switchStatus(lib.Status.Refunding);
        }

        //Returns false if nothing has beenn chaged
        return false;
    }

    /*
     * @notice  Function to give the user their rewards
     * @dev     This function will also mint the tokens to the user
                All calculations are done and variables are gotten in this function
                The only variable needed is the address of the claimer
                Everything else is handled by this function
     * @param   _claimer The address that is claiming the tokens
     */
    function giveTokenRewards(address _claimer)
        internal
        pauseFor(pausers.claiming)
    {
        //Caclulates the user's return for this period
        uint256 returnAmount = lib.calculateReturn(
            balances[_claimer],
            lockedPeriod,
            annualInterestRate
        );

        //Then mint the new tokens to the user and mark themm as claimed
        mint(_claimer, returnAmount);
        claimedRewards[investmentPhase][_claimer] = true;
        emit sentRewards(
            _claimer,
            returnAmount,
            address(this),
            balances[_claimer],
            block.timestamp
        );
    }

    /**
     * @notice  This function will withdraw to an address an amount
     * @notice  This sends all of the user's funds
     * @dev     We are using the withdraw method from the library to transfer an amount to an address
     * @dev     Call this from the claim function
     * @param   _claimer The address that is swapping the tokens for Eth
     */
    function withdraw(address _claimer) internal pauseFor(pausers.withdrawing) {
        //Fund checks
        uint256 userBalance = balanceOf(_claimer);
        require(userBalance > 0, "Withdraw: Must be a non 0 amount of tokens");

        //Burning tokens
        burn(_claimer, userBalance);
        emit tokenSwapedForEth(
            _claimer,
            userBalance,
            address(this),
            balances[_claimer],
            block.timestamp
        );

        //Sending the Eth
        sendEth(_claimer, userBalance);
    }

    /**
     * @dev     Checker function to check if certain periods have finished
     * @return  True if the investment period has finished
     */
    function isInvestmentPeriod() public view returns (bool) {
        return lib.elapsedTimeSince(investmentStartTime) <= lockedPeriod;
    }

    /**
     * @dev     Checker function to check if certain periods have finished
     * @return  True if the claim period has finished
     */
    function isClaimPeriod() public view returns (bool) {
        return lib.elapsedTimeSince(investmentStartTime) <= claimPeriod;
    }

    /**
     * @dev     Checker function to check if certain periods have finished
     * @return  True if the deposit period has finished
     */
    function isDepositPeriod() public view returns (bool) {
        return
            lib.elapsedTimeSince(investmentStartTime) <= depositExpirationDays;
    }

    /**
     * @dev     If any Eth is recived by the contract from the node colapsing
                Set the has node colapsed to true
     * @notice  Emits an event when any Eth is recived by the contract
     */
    receive() external payable {
        uint256 balance = address(this).balance;
        if (balance + msg.value > 0) {
            emit fundsReceived(msg.sender, msg.value, address(this));
            if (address(this).balance >= totalSupply()) {
                hasNodeColapsed = true;
                switchStatus(lib.Status(6));
            }
        }
    }

    //*************************Node funding and controls*************************//
    /**
     * @notice   This function will be use invest the deposited funds to the staking contract.
     * @dev      We first convert the int256 staking Id to uint16, then we check if the stake instance is ready to invest,
                 then we convert the 4 strings given in parameter to bytes or bytes32, finally we call the deposit() function,
                 from the DepositContract, we start the locked period timer and finally, we emit an event
     * @param    _pubkey the payload pubkey
     * @param    _withdrawalCredentials the payload _withdrawal_credentials
     * @param    _signature the payload signature
     * @param    _depositDataRoot the payload deposit_data_root
     */
    function depositToStakingContract(
        string memory _pubkey,
        string memory _withdrawalCredentials,
        string memory _signature,
        string memory _depositDataRoot
    ) external onlyOwner {
        require(
            status == lib.Status.Ready_To_Invest,
            "The stake instance is not ready to invest"
        );
        IDepositContract(0x00000000219ab540356cBB839Cbe05303d7705Fa).deposit{
            value: 32 ether
        }(
            lib.fromStringToBytes(_pubkey),
            lib.fromStringToBytes(_withdrawalCredentials),
            lib.fromStringToBytes(_signature),
            lib.bytesToBytes32(lib.fromStringToBytes(_depositDataRoot))
        );
        switchStatus(lib.Status(2));
        emit ethersSentToTheStakingContract(
            32 ether,
            address(this),
            block.timestamp,
            _pubkey
        );
    }

    /**
     * @dev This is used to refund a full deposit if anything goes wrong with depositing to the Eth2.0 deposit contract
     */
    function refundFullInvestment() public onlyOwner {
        require(
            status == lib.Status.Ready_To_Invest,
            "The stake instance is not ready to invest"
        );
        switchStatus(lib.Status(5));
    }

    /**
     * @notice   This function will send Eth from this contract to target address
     * @param    _reciver the receiver address
     * @param    _value the amount to send
     */
    function sendEth(address _reciver, uint256 _value) internal {
        (bool sent, ) = _reciver.call{value: (_value)}("");
        require(sent, "Failure! Ether not sent.");
        emit transferEth(_reciver, _value, address(this));
    }
}

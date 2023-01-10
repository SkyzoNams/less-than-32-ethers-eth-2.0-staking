# Introduction 
This Solidity smart contract will allow users to stake ethers even if they have less than 32 ethers. <p>Each instance of StakingContract can be deployed as an investment by defining the locked period, the annual interest rate, the deposit expiration period and the claim period.</p> <p>If after the investment periods, the rewards are not claimed by the users, funds are auto reinvested to the staking pool.</p> <p> An IERC20 token is mint for each ether staked (1:1). At the end, a user can claim for his investment + rewards by swaping his token against ethers. All the extra rewards are kept on the contract available for the contract owner.</p>
<p>Events are emited to let the offchains scripts know which action to perform</p>

# There are 5 offchain scrips
1. [event_listener](https://link-url-here.org)
2. [records_handler](https://link-url-here.org)
3. [key_generation](https://link-url-here.org)
4. [scheduled_action](https://link-url-here.org)
5. [keys_handler](https://link-url-here.org)

# Getting Started
1.	Clone the repo
2.  Make sure to have Python 3 installed on your machine (developed with Python 3.7.8)
3.  Go inside the project root you want to execute (/event_listener, /records_handler)
4.  Create your local venv by doing "python3 -m venv ./venv"
5.  Activate the venv by doing "source venv/bin/activate"
6.	From the project rool install all the dependencies by doing "pip install -r requirements.txt"



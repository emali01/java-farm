// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import '@javaswap/java-swap-lib/contracts/math/SafeMath.sol';
import '@javaswap/java-swap-lib/contracts/token/BEP20/IBEP20.sol';
import '@javaswap/java-swap-lib/contracts/token/BEP20/SafeBEP20.sol';
import '@javaswap/java-swap-lib/contracts/access/Ownable.sol';

import "./JavaToken.sol";
import "./libs/IReferral.sol";

// import "@nomiclabs/buidler/console.sol";

// MasterBrew is the master of Java. He can make Java and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once JAVA is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterBrew is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of JAVAs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accJavaPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accJavaPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. JAVAs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that JAVAs distribution occurs.
        uint256 accJavaPerShare; // Accumulated JAVAs per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
    }

    // The JAVA TOKEN!
    JavaToken public java;
    // Dev address.
    address public devaddr;
    // JAVA tokens created per block.
    uint256 public javaPerBlock;
    // Bonus muliplier for early java makers.
    uint256 public BONUS_MULTIPLIER = 1;
    // Deposit Fee address
    address public feeAddress;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when JAVA mining starts.
    uint256 public startBlock;
    uint256 private counter = 1;

    // Referral contract address.
    IReferral public referral;
    // Referral commission rate in basis points.
    uint16 public referralCommissionRate = 200;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event ReferralCommissionPaid(address indexed user, address indexed referrer, uint256 commissionAmount);
    
    modifier entrancyGuard() {
        counter = counter.add(1); // counter adds 1 to the existing 1 so becomes 2
        uint256 guard = counter; // assigns 2 to the "guard" variable
        _;
        require(guard == counter, "That is not allowed"); // 2 == 2? 
    }

    constructor(
        JavaToken _java,
        address _devaddr,
        address _feeAddress,
        uint256 _javaPerBlock,
        uint256 _startBlock
    ) public {
        java = _java;
        feeAddress = _feeAddress;
        devaddr = _devaddr;
        javaPerBlock = _javaPerBlock;
        startBlock = _startBlock;

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: _java,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accJavaPerShare: 0,
            depositFeeBP: 0
        }));

        totalAllocPoint = 1000;

    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        // Validation recomended 
        require (multiplierNumber <= 5, "Invalid value for update multiplier");
        
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IBEP20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 1000, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accJavaPerShare: 0,
            depositFeeBP: _depositFeeBP
        }));
        updateStakingPool();
    }

    // Update the given pool's JAVA allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 1000, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
            updateStakingPool();
        }
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(3);
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(points);
            poolInfo[0].allocPoint = points;
        }
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending JAVAs on frontend.
    function pendingJava(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accJavaPerShare = pool.accJavaPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 javaReward = multiplier.mul(javaPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accJavaPerShare = accJavaPerShare.add(javaReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accJavaPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }


    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 javaReward = multiplier.mul(javaPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        java.mint(devaddr, javaReward.div(10));
        java.mint(address(this), javaReward);
        pool.accJavaPerShare = pool.accJavaPerShare.add(javaReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterBrew for JAVA allocation.
    function deposit(uint256 _pid, uint256 _amount, address _referrer) public entrancyGuard() {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        if (_amount > 0 && address(referral) != address(0) && _referrer != address(0) && _referrer != msg.sender) {
            referral.recordReferral(msg.sender, _referrer);
        }

        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accJavaPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeJavaTransfer(msg.sender, pending);
                payReferralCommission(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            
            // Thanks for RugDoc advice
            uint256 _before = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            uint256 _after = pool.lpToken.balanceOf(address(this));
            _amount = _after.sub(_before);
            // Thanks for RugDoc advice
            
            if(pool.depositFeeBP > 0){
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                _amount = _amount.sub(depositFee);
            }
            
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accJavaPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterBrew.
    function withdraw(uint256 _pid, uint256 _amount) public entrancyGuard() {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accJavaPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeJavaTransfer(msg.sender, pending);
            payReferralCommission(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accJavaPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public entrancyGuard() {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe java transfer function, just in case if rounding error causes pool to not have enough JAVAs.
    function safeJavaTransfer(address _to, uint256 _amount) internal {
        uint256 javaBal = java.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > javaBal) {
            transferSuccess = java.transfer(_to, javaBal);
        } else {
            transferSuccess = java.transfer(_to, _amount);
        }
        require(transferSuccess, "safeJavaTransfer: transfer failed");
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        require(_devaddr != address(0), "Address cant be 0");
        devaddr = _devaddr;
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _javaPerBlock) public onlyOwner {
        // Validation recomended 
        require (_javaPerBlock <= 50 ether, "Invalid value for update javaPerBlock");
        
        massUpdatePools();
        javaPerBlock = _javaPerBlock;
    }

    // Allows to update the referral contract. It must be approved and executed by Governance
    function setReferral(IReferral _referral) public onlyOwner {
        referral = _referral;
    }
    
    // Allows to update the fee address. It must be approved and executed by Governance
    function setFeeAddress(address _feeAddress) public onlyOwner {
        require(_feeAddress != address(0), "Address cant be 0");
        feeAddress = _feeAddress;
    }

    // Updates must be approved and executed by Governance
    function setReferralCommissionRate(uint16 _referralCommissionRate) public onlyOwner {
        require(_referralCommissionRate <= 500, "Invalid value for Referral Commision Rate");
        referralCommissionRate = _referralCommissionRate;
    }

    // Pay referral commission to the referrer who referred this user.
    function payReferralCommission(address _user, uint256 _pending) internal {
        if (address(referral) != address(0) && referralCommissionRate > 0) {
            address referrer = referral.getReferrer(_user);
            uint256 commissionAmount = _pending.mul(referralCommissionRate).div(10000);

            if (referrer != address(0) && commissionAmount > 0) {
                java.mint(referrer, commissionAmount);
                emit ReferralCommissionPaid(_user, referrer, commissionAmount);
            }
        }
    }
}

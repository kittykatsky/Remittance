pragma solidity ^0.6.0;

import "./Pausable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

/// @author Kat
/// @title A contract for transfering ethereum through an intermediary 
contract Remittance is Pausable {

    using SafeMath for uint;

    // Remittance deadline cant be more than 2 hours into the future
    uint16 constant CUTOFF_LIMIT = 2 hours;
    // Remittance fee
    uint fee;

    // Struct to hold information about individual remittances
    struct remittanceStruct {
        address from;
        uint amount;
        uint deadline;
    } 

    // Remittance balance mapping, maps a given puzzle to a second mapping
    // linking an address (the converter) to an amount (the remittance)
    mapping(bytes32 => remittanceStruct) public remittances;
    // mapping that holds fees payed out to contract owner
    mapping(address => uint) private fees;

    event LogNewRemittance(address indexed sender, address indexed converter, uint amount, uint deadline);
    event LogFundsReleased(address indexed sender, address indexed converter, uint amount);
    event LogFundsReclaimed(address indexed sender, uint amount);

    constructor (
        bool _pauseState, 
        uint _fee
    ) 
        Pausable(_pauseState) 
        public 
    {
        fee = _fee;
    }

    /// List fees collected by contract
    /// @dev since the fees mapping is private the 
    /// owner needs to be able to find out the amount of fees collected
	/// @return amount the amount of fees collected
    function listFees() external view onlyOwner returns (uint amount)
    {
        amount = fees[msg.sender];
    }

    /// Withdraw fees from created remittances
    /// @dev allowd the owner to withdraw collected fees
	/// @return success function succeeded 

    function withdrawFees() external onlyOwner returns (bool success)
    {
        uint amount = fees[msg.sender];
        require(amount > 0, 'No ether available');
        fees[msg.sender] = 0;

        (success, ) = msg.sender.call{value: amount}("");
        require(success, 'Transfer failed!');
        return true;
    }

    /// Generate a unique puzzle for this contract
    /// @param converterAddress address of converter
    /// @param puzzlePiece puzzle piece provided by recipient
    /// @dev puzzle combines the address of the converter, 
    /// the contract and the puzzle piece provided by the reciever
	/// @return puzzle a hash generated from the input paramaters
    function generatePuzzle(address converterAddress, bytes32 puzzlePiece)
        public
        view
        returns (bytes32 puzzle)
    {
        require(converterAddress != address(0x0), 'address needs to be specified');
        puzzle = keccak256(abi.encodePacked(converterAddress, puzzlePiece, address(this)));
    }

    /// Generates a remittance
    /// @param converter address of converter 
    /// @param puzzle puzzle provided to unlock remittance
    /// @param cutOff point set for the remittance after which it
    /// is no longer valid
    function createRemittance(
        address payable converter, 
        bytes32 puzzle, 
        uint cutOff
    )
        external
        payable
        whenRunning
    {
        require(cutOff <= CUTOFF_LIMIT, 'deadline cant be more than two hours into future');
        require(remittances[puzzle].from == address(0x0), 'Secret already in use');

        uint deadline = block.timestamp.add(cutOff); 

        remittances[puzzle] = remittanceStruct({
            from:msg.sender, 
            amount:msg.value.sub(fee),
            deadline:deadline    
        });
        emit LogNewRemittance(msg.sender, converter, msg.value, deadline);

        address contractOwner = getOwner();
        uint newFee = fees[contractOwner].add(fee);
        fees[contractOwner] = newFee;
    }

    /// Release the remittance
    /// @param puzzlePiece used to unlock remittance
    /// @dev allows converter to withdraw the alloted funds
	/// @return success true if succesfull
    function releaseFunds(bytes32 puzzlePiece) 
        public
        whenRunning
        returns (bool success)
    {
        bytes32 puzzle = generatePuzzle(msg.sender, puzzlePiece);
        (uint amount, uint deadline, address from) = retrieveRemInfo(puzzle);
        require(block.timestamp <= deadline, 'Remittance has lapsed');
        require(amount > 0, 'Remittance is empty');

        remittances[puzzle].amount = 0;
        remittances[puzzle].deadline = 0;
        emit LogFundsReleased(from, msg.sender, amount);

        (success, ) = msg.sender.call{value: amount}("");
        require(success, 'Transfer failed!');
        return true;
    } 

    /// Reclaim funds from expired remittance
    /// @param converterAddress remittance converter address
    /// @param puzzlePiece used to unlock remittance
    /// @dev allows sender to withdraw their sent funds
	/// @return success true if succesfull
    function reclaimFunds(address converterAddress, bytes32 puzzlePiece)
        public
        returns (bool success)
    {
        bytes32 puzzle = generatePuzzle(converterAddress, puzzlePiece);
        (uint amount, uint deadline, address from) = retrieveRemInfo(puzzle);
        require(msg.sender == from, 'Only sender can reclaim funds');
        require(amount > 0, 'Remittance is empty');
        require(block.timestamp > deadline, 'Remittance needs to expire');

        remittances[puzzle].amount = 0;
        remittances[puzzle].deadline = 0;
        emit LogFundsReclaimed(msg.sender, amount);

        (success, ) = msg.sender.call{value: amount}("");
        require(success, 'Transfer failed!');
        return true;
    }

    /// change contract owner
    /// @param newOwner - address of new owner
    /// @dev additional logic for releasing leftover fees 
    /// if owner forgot to claim them before assinging new owner
    function transferOwnership(address newOwner) override public onlyOwner {
        uint leftOverFees = fees[msg.sender];
        if (leftOverFees > 0)
        {
            fees[msg.sender] = 0;
            (bool success, ) = msg.sender.call{value: leftOverFees}("");
            require(success, 'Remaining fee transfer failed');
        }
        super.transferOwnership(newOwner);

    }

    /// Return Remittance struct data
    /// @param puzzle puzzle associated with remittance struct
    /// @dev repeated code moved from release/reclaim funds to its own function
	/// @return amount amount of ether in remittance
	/// @return deadline remittance deadline
	/// @return from remittance created
    function retrieveRemInfo(bytes32 puzzle) 
        private 
        returns(uint amount, uint deadline, address from)
    {
        amount = remittances[puzzle].amount;
        from = remittances[puzzle].from;
        deadline = remittances[puzzle].deadline;
    }
    
}

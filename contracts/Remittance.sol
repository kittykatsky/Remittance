pragma solidity ^0.6.0;

import "./Pausable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

/// @author Kat
/// @title A contract for transfering ethereum through an intermediary 
contract Remittance is Pausable {

    using SafeMath for uint;

    // Remittance deadlince cant be more than 2 hours into the future
    uint16 constant DEADLINE_LIMIT = 7200;
    // Remittance fee
    uint fee;

    // Struct to hold information about individual remittances
    struct remittanceStruct {
        address payable from;
        uint amount;
        uint deadline;
    } 

    // Remittance balance mapping, maps a given puzzle to a second mapping
    // linking an address (the converter) to an amount (the remittance)
    mapping(bytes32 => remittanceStruct) public remittances;
    // mapping that holds fees payed out to contract owner
    mapping(address => uint) private fees;

    event logNewRemittance(address indexed sender, address indexed converter, uint amount, uint deadline);
    event logFundsReleased(address indexed sender, uint amount, uint releasedAt);
    event logFundsReclaimed(address indexed sender, uint amount, uint reclaimedAt);

    constructor (bool _pauseState, uint _fee) Pausable(_pauseState) public {fee = _fee;}

    /// Generates a remittance
    /// @param converter address of converter 
    /// @param puzzle puzzle provided to unlock remittance
    /// @param deadline deadline set for the remittance
    function createRemittance(
        address payable converter, 
        bytes32 puzzle, 
        uint deadline
    )
        external
        payable
        whenRunning
    {
        require(deadline <= DEADLINE_LIMIT, 'Deadline cant be more than two hours into future');
        require(msg.value > fee, 'deposited amount need to be larger than fee');
        require(remittances[puzzle].from == address(0x0), 'Secret already in use');

        remittances[puzzle].from = msg.sender;
        remittances[puzzle].amount = msg.value.sub(fee);
        remittances[puzzle].deadline = block.timestamp + deadline; 
        emit logNewRemittance(msg.sender, converter, msg.value, deadline);
        fees[getOwner()] = fees[getOwner()].add(fee);
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
        puzzle = keccak256(abi.encode(converterAddress, puzzlePiece, address(this)));
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
        (uint amount, uint deadline, ) = retrieveRemInfo(puzzle);
        require(block.timestamp <= deadline, 'Remittance has lapsed');
        require(amount > 0, 'Remittance is empty');

        remittances[puzzle].amount = 0;
        remittances[puzzle].deadline = 0;
        emit logFundsReleased(msg.sender, amount, block.timestamp);

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
        (uint amount, uint deadline, address payable from) = retrieveRemInfo(puzzle);
        require(msg.sender == from, 'Only sender can reclaim funds');
        require(amount > 0, 'Remittance is empty');
        require(block.timestamp >= deadline, 'Remittance needs to expire');

        remittances[puzzle].amount = 0;
        remittances[puzzle].deadline = 0;
        emit logFundsReclaimed(msg.sender, amount, block.timestamp);

        (success, ) = msg.sender.call{value: amount}("");
        require(success, 'Transfer failed!');
        return true;
    }

    /// Return Remittance struct data
    /// @param puzzle puzzle associated with remittance struct
    /// @dev repeated code moved from release/reclaim funds to its own function
	/// @return amount amount of ether in remittance
	/// @return deadline remittance deadline
	/// @return from remittance created
    function retrieveRemInfo(bytes32 puzzle) 
        private 
        returns(uint amount, uint deadline, address payable from)
    {
        amount = remittances[puzzle].amount;
        from = remittances[puzzle].from;
        deadline = remittances[puzzle].deadline;

        return (amount, deadline, from);
    }

    /// Withdraw fees from created remittances
    /// @dev allowd the owner to withdraw collected fees
	/// @return success function succeeded 
    function withdrawFees() public onlyOwner returns (bool success)
    {
        uint amount = fees[msg.sender];
        require(amount > 0, 'No ether available');
        fees[msg.sender] = 0;

        (success, ) = msg.sender.call{value: amount}("");
        require(success, 'Transfer failed!');
        return true;
    }
}

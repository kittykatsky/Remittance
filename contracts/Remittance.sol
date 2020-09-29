pragma solidity ^0.6.0;

import "./Pausable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

/// @author Kat
/// @title A contract for transfering ethereum through an intermediary 
contract Remittance is Pausable {

    using SafeMath for uint;

    // Remittance deadline cant be more than 2 hours into the future
    uint32 constant CUTOFF_LIMIT = 12 hours;
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

    event LogNewRemittance(address indexed sender, bytes32 indexed puzzle, uint amount, uint deadline);
    event LogFundsReleased(address indexed converter, bytes32 indexed puzzle, uint amount);
    event LogFundsReclaimed(address indexed sender, bytes32 indexed puzzle, uint amount);
    event LogFeesRetrieved(address indexed sender, uint amount);

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
    function listFees() external view returns (uint amount)
    {
        amount = fees[msg.sender];
    }

    /// Withdraw fees from created remittances
    /// @dev allowd the owner to withdraw collected fees
	/// @return success function succeeded 

    function withdrawFees() external returns (bool success)
    {
        uint amount = fees[msg.sender];
        require(amount > 0, 'No ether available');
        fees[msg.sender] = 0;

        emit LogFeesRetrieved(msg.sender, amount);
        (success, ) = msg.sender.call{value: amount}("");
        require(success, 'Transfer failed!');
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
    /// @param puzzle puzzle provided to unlock remittance
    /// @param cutOff point set for the remittance after which it
    /// is no longer valid
    function createRemittance(
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
        uint amount = msg.value.sub(fee);

        remittances[puzzle] = remittanceStruct({
            from: msg.sender, 
            amount: amount,
            deadline: deadline    
        });
        emit LogNewRemittance(msg.sender, puzzle, amount, deadline);

        address contractOwner = getOwner();
        
        fees[contractOwner] = fees[contractOwner].add(fee);
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
        uint amount = remittances[puzzle].amount;

        require(block.timestamp <= remittances[puzzle].deadline, 'Remittance has lapsed');
        require(amount > 0, 'Remittance is empty');

        remittances[puzzle].amount = 0;
        remittances[puzzle].deadline = 0;
        emit LogFundsReleased(msg.sender, puzzle, amount);

        (success, ) = msg.sender.call{value: amount}("");
        require(success, 'Transfer failed!');
    } 

    /// reclaim funds from expired remittance
    /// @param puzzle used to unlock remittance
    /// @dev allows sender to withdraw their sent funds
	/// @return success true if succesfull
    function reclaimFunds(bytes32 puzzle)
        public
        returns (bool success)
    {
        uint amount = remittances[puzzle].amount;

        require(msg.sender == remittances[puzzle].from, 'Only sender can reclaim funds');
        require(amount > 0, 'Remittance is empty');
        require(block.timestamp > remittances[puzzle].deadline, 'Remittance needs to expire');

        remittances[puzzle].amount = 0;
        remittances[puzzle].deadline = 0;
        emit LogFundsReclaimed(msg.sender, puzzle, amount);

        (success, ) = msg.sender.call{value: amount}("");
        require(success, 'Transfer failed!');
    }
}

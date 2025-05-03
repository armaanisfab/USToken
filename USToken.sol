// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract USToken {
    uint256 public clubCount;
    uint256 public constant INITIAL_TOKENS = 10e18; // 10 USTokens in wei
    uint256 public constant ATTENDANCE_REWARD = 1e18; // 1 USToken per session
    uint256 public constant PENALTY_PER_MISS = 0.5e18; // 0.5 USTokens per miss

    mapping(address => uint256) public balances;
    mapping(address => uint256) public clubMembership;
    mapping(address => bool) public hasReceivedInitialTokens;
    mapping(address => uint256[]) public organizerClubs; // Added mapping

    struct Session {
        string sessionIdentifier;
        mapping(address => bool) attended;
        mapping(address => uint256) bonusAmount;
        address[] attendees;
    }

    struct Club {
        string name;
        string courseCode;
        address leader;
        string schedule;
        string description;
        string requirements;
        uint256 sessionCount;
        mapping(address => bool) members;
        mapping(address => uint256) attendanceCount;
        mapping(address => uint256) stakedInClub;
        mapping(address => uint256) earnedTokens;
        address[] memberList;
        bool active;
        mapping(uint256 => Session) sessions;
        mapping(string => bool) sessionIdentifierUsed;
    }
    mapping(uint256 => Club) public clubs;

    event TokensMinted(address indexed to, uint256 amount);
    event ClubCreated(uint256 clubId, string name, string courseCode, address leader);
    event MemberJoined(uint256 clubId, address member, uint256 stake);
    event DailyAttendanceSubmitted(uint256 clubId, uint256 sessionId, string sessionIdentifier);
    event AttendanceMarked(uint256 clubId, uint256 sessionId, address member, bool attended);
    event BonusMinted(uint256 clubId, uint256 sessionId, address member, uint256 amount);
    event PenaltyApplied(uint256 clubId, uint256 sessionId, address member, uint256 penalty);

    modifier onlyLeader(uint256 clubId) {
        require(msg.sender == clubs[clubId].leader, "Only club leader can call this function");
        _;
    }

    constructor() {
        clubCount = 0;
    }

    function createClub(
        string memory name,
        string memory courseCode,
        string memory schedule,
        string memory description,
        string memory requirements
    ) external {
        if (!hasReceivedInitialTokens[msg.sender]) {
            balances[msg.sender] += INITIAL_TOKENS;
            hasReceivedInitialTokens[msg.sender] = true;
            emit TokensMinted(msg.sender, INITIAL_TOKENS);
        }
        require(balances[msg.sender] >= INITIAL_TOKENS, "Insufficient tokens");

        clubCount = clubCount + 1;
        Club storage club = clubs[clubCount];
        club.name = name;
        club.courseCode = courseCode;
        club.leader = msg.sender;
        club.schedule = schedule;
        club.description = description;
        club.requirements = requirements;
        club.active = true;
        club.members[msg.sender] = true;
        club.memberList.push(msg.sender);
        club.stakedInClub[msg.sender] = INITIAL_TOKENS;
        balances[msg.sender] -= INITIAL_TOKENS;
        clubMembership[msg.sender] = clubCount;

        organizerClubs[msg.sender].push(clubCount); // Add club to organizer's list

        emit ClubCreated(clubCount, name, courseCode, msg.sender);
        emit MemberJoined(clubCount, msg.sender, INITIAL_TOKENS);
    }

    function joinClub(uint256 clubId) external {
        if (!hasReceivedInitialTokens[msg.sender]) {
            balances[msg.sender] += INITIAL_TOKENS;
            hasReceivedInitialTokens[msg.sender] = true;
            emit TokensMinted(msg.sender, INITIAL_TOKENS);
        }
        require(clubId <= clubCount && clubId > 0, "Invalid club ID");
        Club storage club = clubs[clubId];
        require(club.active, "Club is not active");
        require(!club.members[msg.sender], "Already a member");
        require(clubMembership[msg.sender] == 0, "Already in a club");
        require(balances[msg.sender] >= INITIAL_TOKENS, "Insufficient tokens");

        club.members[msg.sender] = true;
        club.memberList.push(msg.sender);
        club.stakedInClub[msg.sender] = INITIAL_TOKENS;
        balances[msg.sender] -= INITIAL_TOKENS;
        clubMembership[msg.sender] = clubId;
        emit MemberJoined(clubId, msg.sender, INITIAL_TOKENS);
    }

    function submitDailyAttendance(
        uint256 clubId,
        string memory sessionIdentifier,
        address[] memory members,
        bool[] memory attended,
        uint256[] memory bonusAmounts
    ) external onlyLeader(clubId) {
        require(clubId <= clubCount && clubId > 0, "Invalid club ID");
        Club storage club = clubs[clubId];
        require(club.active, "Club is not active");
        require(!club.sessionIdentifierUsed[sessionIdentifier], "Session identifier already used");
        require(members.length == attended.length && members.length == bonusAmounts.length, "Input arrays must match");
        require(members.length <= club.memberList.length, "Too many members");

        club.sessionIdentifierUsed[sessionIdentifier] = true;
        club.sessionCount = club.sessionCount + 1;
        uint256 sessionId = club.sessionCount;
        Session storage session = club.sessions[sessionId];
        session.sessionIdentifier = sessionIdentifier;

        uint256 totalPenalty = 0;
        address[] memory attendees = new address[](members.length);
        uint256 attendeeCount = 0;

        for (uint256 i = 0; i < members.length; i++) {
            address member = members[i];
            require(club.members[member], "Not a member");

            session.attended[member] = attended[i];
            session.bonusAmount[member] = bonusAmounts[i];

            if (attended[i]) {
                club.attendanceCount[member] = club.attendanceCount[member] + 1;
                balances[member] = balances[member] + ATTENDANCE_REWARD;
                club.earnedTokens[member] = club.earnedTokens[member] + ATTENDANCE_REWARD;
                emit TokensMinted(member, ATTENDANCE_REWARD);

                if (bonusAmounts[i] > 0) {
                    balances[member] = balances[member] + bonusAmounts[i];
                    club.earnedTokens[member] = club.earnedTokens[member] + bonusAmounts[i];
                    emit BonusMinted(clubId, sessionId, member, bonusAmounts[i]);
                    emit TokensMinted(member, bonusAmounts[i]);
                }

                attendees[attendeeCount] = member;
                attendeeCount = attendeeCount + 1;
            } else {
                if (club.stakedInClub[member] >= PENALTY_PER_MISS) {
                    club.stakedInClub[member] = club.stakedInClub[member] - PENALTY_PER_MISS;
                    totalPenalty = totalPenalty + PENALTY_PER_MISS;
                    emit PenaltyApplied(clubId, sessionId, member, PENALTY_PER_MISS);
                }
            }
            emit AttendanceMarked(clubId, sessionId, member, attended[i]);
        }

        address[] memory finalAttendees = new address[](attendeeCount);
        for (uint256 i = 0; i < attendeeCount; i++) {
            finalAttendees[i] = attendees[i];
        }
        session.attendees = finalAttendees;

        if (totalPenalty > 0 && attendeeCount > 0) {
            uint256 rewardPerMember = totalPenalty / attendeeCount;
            for (uint256 i = 0; i < attendeeCount; i++) {
                address m = finalAttendees[i];
                balances[m] = balances[m] + rewardPerMember;
                club.earnedTokens[m] = club.earnedTokens[m] + rewardPerMember;
                emit TokensMinted(m, rewardPerMember);
            }
        }

        emit DailyAttendanceSubmitted(clubId, sessionId, sessionIdentifier);
    }

    function getClubDetails(uint256 clubId) external view returns (
        string memory name,
        string memory courseCode,
        address leader,
        string memory schedule,
        string memory description,
        string memory requirements,
        bool active
    ) {
        require(clubId <= clubCount && clubId > 0, "Invalid club ID");
        Club storage club = clubs[clubId];
        return (
            club.name,
            club.courseCode,
            club.leader,
            club.schedule,
            club.description,
            club.requirements,
            club.active
        );
    }

    function getMemberStats(uint256 clubId, address member) external view returns (
        uint256 attendanceCount,
        uint256 staked,
        uint256 earnedTokens
    ) {
        require(clubId <= clubCount && clubId > 0, "Invalid club ID");
        Club storage club = clubs[clubId];
        return (club.attendanceCount[member], club.stakedInClub[member], club.earnedTokens[member]);
    }

    function getSessionAttendance(uint256 clubId, uint256 sessionId, address member) external view returns (
        bool attended,
        uint256 bonusAmount
    ) {
        require(clubId <= clubCount && clubId > 0, "Invalid club ID");
        Club storage club = clubs[clubId];
        require(sessionId <= club.sessionCount && sessionId > 0, "Invalid session ID");
        Session storage session = club.sessions[sessionId];
        return (session.attended[member], session.bonusAmount[member]);
    }

    function getLeaderboard(uint256 clubId) external view returns (
        address[] memory members,
        uint256[] memory totalTokens
    ) {
        require(clubId <= clubCount && clubId > 0, "Invalid club ID");
        Club storage club = clubs[clubId];
        members = club.memberList;
        totalTokens = new uint256[](members.length);
        for (uint256 i = 0; i < members.length; i++) {
            address m = members[i];
            totalTokens[i] = club.stakedInClub[m] + club.earnedTokens[m];
        }
        return (members, totalTokens);
    }

    function getOrganizerClubs(address user) external view returns (uint256[] memory) {
        return organizerClubs[user]; // Updated to use mapping
    }

    function getParticipantClub(address user) external view returns (uint256) {
        return clubMembership[user];
    }
}
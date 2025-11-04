import 'package:flutter/material.dart';
import 'view_transaction_screen.dart';
import 'settings/account_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String selectedFilter = 'All';
  String? selectedStatus;
  DateTime? selectedDate;

  // All transaction data
  final List<Map<String, dynamic>> allTransactions = [
    {
      'id': 'Transaction ID: 000000',
      'recipient': 'Recipient: Ashanti Villadiego',
      'locker': 'Locker: Smacker 222',
      'status': 'Delivered',
      'color': Colors.blue,
      'timestamp': DateTime(2025, 10, 27, 10, 30),
    },
    {
      'id': 'Transaction ID: 000000',
      'recipient': 'Recipient: Kimberly Isip',
      'locker': 'Locker: Smacker 222',
      'status': 'Claimed',
      'color': Colors.green,
      'timestamp': DateTime(2025, 10, 28, 14, 15),
    },
    {
      'id': 'Transaction ID: 000000',
      'recipient': 'Recipient: Kaiwen Chen',
      'locker': 'Locker: Smacker 222',
      'status': 'Failed',
      'color': Colors.red,
      'timestamp': DateTime(2025, 11, 1, 9, 45),
    },
  ];

  // Get filtered transactions based on selected filter
  List<Map<String, dynamic>> get filteredTransactions {
    if (selectedFilter == 'All') {
      return allTransactions;
    } else if (selectedFilter == 'Filter By Date') {
      if (selectedDate == null) return allTransactions;
      // Filter by selected date - compare only the date part (year, month, day)
      return allTransactions.where((t) {
        DateTime transactionDate = t['timestamp'];
        return transactionDate.year == selectedDate!.year &&
               transactionDate.month == selectedDate!.month &&
               transactionDate.day == selectedDate!.day;
      }).toList();
    } else if (selectedFilter == 'Filter By Status') {
      if (selectedStatus == null) return allTransactions;
      return allTransactions.where((t) => t['status'] == selectedStatus).toList();
    }
    return allTransactions;
  }

  Future<void> _showStatusFilterDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Filter By Status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('All'),
                onTap: () {
                  Navigator.pop(context, null);
                },
              ),
              ListTile(
                title: const Text('Delivered'),
                onTap: () {
                  Navigator.pop(context, 'Delivered');
                },
              ),
              ListTile(
                title: const Text('Claimed'),
                onTap: () {
                  Navigator.pop(context, 'Claimed');
                },
              ),
              ListTile(
                title: const Text('Failed'),
                onTap: () {
                  Navigator.pop(context, 'Failed');
                },
              ),
            ],
          ),
        );
      },
    );

    if (result != null || result == null) {
      setState(() {
        selectedStatus = result;
        selectedFilter = 'Filter By Status';
      });
    }
  }

  Future<void> _showDatePicker() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (picked != null) {
      setState(() {
        selectedDate = picked;
        selectedFilter = 'Filter By Date';
      });
    }
  }

  void _handleFilterTap(String filterName) {
    if (filterName == 'Filter By Status') {
      _showStatusFilterDialog();
    } else if (filterName == 'Filter By Date') {
      _showDatePicker();
    } else {
      setState(() {
        selectedFilter = filterName;
        selectedStatus = null;
        selectedDate = null;
      });
    }
  }

  // Calculate totals dynamically based on all transactions
  int get totalTransactions => allTransactions.length;
  
  int get totalCompleted => allTransactions.where((t) => 
    t['status'] == 'Delivered' || t['status'] == 'Claimed'
  ).length;
  
  int get totalFailed => allTransactions.where((t) => 
    t['status'] == 'Failed'
  ).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          // Blue header with user info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
            decoration: const BoxDecoration(
              color: Color(0xFF5B9BFF),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person,
                    color: Color(0xFF5B9BFF),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      UserData.fullName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ID: ${UserData.userId}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Contact Information Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'Contact Information',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.phone_outlined, color: Colors.black54, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'Phone Number:',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        UserData.phoneNumber,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.email_outlined, color: Colors.black54, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'Email:',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          UserData.email,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Transaction Stats
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C3E50),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '$totalTransactions',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Total Transactions',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C3E50),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '$totalCompleted',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Total Completed',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C3E50),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '$totalFailed',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Total Failed',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          
          // Filter tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildFilterTab('All'),
                const SizedBox(width: 6),
                _buildFilterTab('Filter By Date'),
                const SizedBox(width: 6),
                _buildFilterTab('Filter By Status'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          
          // Transaction List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filteredTransactions.length,
              itemBuilder: (context, index) {
                final transaction = filteredTransactions[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildTransactionCard(
                    transaction['id'],
                    transaction['recipient'],
                    transaction['locker'],
                    transaction['status'],
                    transaction['color'],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTab(String text) {
    final bool isSelected = selectedFilter == text;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          _handleFilterTap(text);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF5B9BFF) : Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? const Color(0xFF5B9BFF) : Colors.grey.shade300,
            ),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(
    String transactionId,
    String recipient,
    String locker,
    String status,
    Color statusColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  transactionId,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  status,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            recipient,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                locker,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black54,
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ViewTransactionScreen(
                        transaction: {
                          'id': transactionId,
                          'recipient': recipient,
                          'locker': locker,
                          'status': status,
                          'color': statusColor,
                        },
                      ),
                    ),
                  );
                },
                child: const Text(
                  'View Details >',
                  style: TextStyle(
                    color: Color(0xFF5B9BFF),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

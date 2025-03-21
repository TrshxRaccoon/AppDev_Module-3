import 'package:flutter/material.dart';
import 'package:flutter_module_3/screens/login_screen.dart';
import 'package:flutter_module_3/secrets.dart';
import 'package:http/http.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  TextEditingController symbolController = TextEditingController();
  TextEditingController buyDateController = TextEditingController();
  TextEditingController sellDateController = TextEditingController();
  TextEditingController quantityController = TextEditingController();

  String pricePreference = 'Average';
  double? profitLoss;
  List<Map<String, dynamic>> recentCalculations = [];

  @override
  void initState() {
    super.initState();
    fetchRecentCalculations();
  }

  String greet() {
    int hour = DateTime.now().hour;
    if (hour >= 4 && hour < 12) {
      return "Good morning";
    } else if (hour >= 12 && hour < 17) {
      return "Good afternoon";
    } else {
      return "Good evening";
    }
  }

  Future<Map<String, dynamic>?> fetchStockData(String symbol) async {
    final response = await get(Uri.parse(
        'https://www.alphavantage.co/query?function=TIME_SERIES_DAILY&symbol=$symbol&apikey=$alphaVantageAPIKey'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      return null;
    }
  }

  double getPriceBasedOnPreference(Map<String, dynamic> dayData) {
    double high = double.parse(dayData['2. high']);
    double low = double.parse(dayData['3. low']);
    if (pricePreference == 'High') return high;
    if (pricePreference == 'Low') return low;
    return (high + low) / 2;
  }

  Future<void> calculateAndStoreResult() async {
    String symbol = symbolController.text.trim();
    String buyDate = buyDateController.text.trim();
    String sellDate = sellDateController.text.trim();
    int quantity = int.tryParse(quantityController.text.trim()) ?? 0;

    if (symbol.isEmpty ||
        buyDate.isEmpty ||
        sellDate.isEmpty ||
        quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Please fill all fields with valid data.")));
      return;
    }

    try {
      final data = await fetchStockData(symbol);

      if (data == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not fetch data. Check your internet connection.')),
        );
        return;
      }

      if (data.containsKey('Error Message')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid stock symbol entered.')),
        );
        return;
      }

      final timeSeries = data['Time Series (Daily)'];

      if (timeSeries == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Data unavailable for this symbol.')),
        );
        return;
      }

      if (!timeSeries.containsKey(buyDate)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid buy date entered: $buyDate.')),
        );
        return;
      }

      if (!timeSeries.containsKey(sellDate)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid sell date entered: $sellDate.')),
        );
        return;
      }

      double buyPrice = getPriceBasedOnPreference(timeSeries[buyDate]);
      double sellPrice = getPriceBasedOnPreference(timeSeries[sellDate]);
      double result = (sellPrice - buyPrice) * quantity;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('calculations')
          .add({
        'stock': symbol,
        'buyDate': buyDate,
        'sellDate': sellDate,
        'quantity': quantity,
        'profitOrLoss': result,
        'timestamp': FieldValue.serverTimestamp(),
      });

      setState(() {
        profitLoss = result;
      });

      await fetchRecentCalculations();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Calculation complete for $symbol!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An unexpected error occurred.')),
      );
    }
  }

  Future<void> fetchRecentCalculations() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('calculations')
          .orderBy('timestamp', descending: true)
          .limit(5)
          .get();

      final fetchedData = snapshot.docs
          .map((doc) => doc.data())
          .toList()
          .cast<Map<String, dynamic>>();

      setState(() {
        recentCalculations = fetchedData;
      });
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void signOut() async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (context) => LoginPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Color(0xFF1A1B22),
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(
              Icons.menu,
              color: Colors.white,
            ),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
      ),
      backgroundColor: Color(0xFF1A1B22),
      drawer: Drawer(
        backgroundColor: Color(0xFF2F343D),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                    child: Text(
                      'Recent Calculations',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.white),
                    ),
                  ),
                  if (recentCalculations.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text('No recent calculations!'),
                    )
                  else
                    ...recentCalculations.map((calc) {
                      bool isProfit = calc['profitOrLoss'] >= 0;
                      return ListTile(
                        tileColor: isProfit
                            ? Color.fromARGB(255, 19, 68, 22)
                            : Color.fromARGB(255, 119, 18, 18),
                        title: Text(
                          "\$${calc['stock']}",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color:
                                isProfit ? Colors.green[100] : Colors.red[100],
                          ),
                        ),
                        subtitle: Text(
                          "Buy: ${calc['buyDate']} | Sell: ${calc['sellDate']}\nQty: ${calc['quantity']} | P/L: \$${calc['profitOrLoss'].toStringAsFixed(2)}",
                          style: TextStyle(color: Colors.white),
                        ),
                      );
                    }),
                ],
              ),
            ),
            Divider(color: Colors.white60),
            ListTile(
              leading: Icon(Icons.logout, color: Colors.red[100]),
              title: Text('Sign Out', style: TextStyle(color: Colors.red[100])),
              onTap: signOut,
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${greet()}!",
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 28)),
              SizedBox(height: 100),
              Row(
                children: [
                  Text(
                    "\$",
                    style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                  ),
                  SizedBox(
                    width: 10,
                  ),
                  Expanded(
                    child: TextField(
                      controller: symbolController,
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                          labelText: 'Stock Symbol',
                          labelStyle: TextStyle(color: Colors.white)),
                    ),
                  )
                ],
              ),
              Row(
                children: [
                  Expanded(
                      child: TextField(
                          controller: buyDateController,
                          style: TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                              labelText: 'Purchase Date (YYYY-MM-DD)',
                              labelStyle: TextStyle(color: Colors.white)))),
                  SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                          controller: sellDateController,
                          style: TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                              labelText: 'Sell Date (YYYY-MM-DD)',
                              labelStyle: TextStyle(color: Colors.white)))),
                ],
              ),
              TextField(
                  controller: quantityController,
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                      labelText: 'Quantity',
                      labelStyle: TextStyle(color: Colors.white))),
              SizedBox(height: 10),
              Row(children: [
                Text(
                  "Price Range:",
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                SizedBox(
                  width: 10,
                ),
                DropdownButton<String>(
                  value: pricePreference,
                  dropdownColor: Color(0xFF2F343D),
                  onChanged: (value) {
                    setState(() {
                      pricePreference = value!;
                    });
                  },
                  items: ['Average', 'High', 'Low']
                      .map((value) => DropdownMenuItem(
                            value: value,
                            child: Text(
                              value,
                              style: TextStyle(color: Colors.white),
                            ),
                          ))
                      .toList(),
                ),
              ]),
              SizedBox(height: 15),
              ElevatedButton(
                onPressed: calculateAndStoreResult,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Color.fromARGB(255, 173, 188, 219)),
                child: Text(
                  'Calculate Profit/Loss',
                  style: TextStyle(color: Colors.black),
                ),
              ),
              if (profitLoss != null)
                Container(
                  margin: EdgeInsets.symmetric(vertical: 20),
                  padding: EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: profitLoss! >= 0 ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    (profitLoss! > 0)
                        ? "Your Profit: \$${profitLoss!.toStringAsFixed(2)}"
                        : "Your Loss: \$${profitLoss!.toStringAsFixed(2)}",
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

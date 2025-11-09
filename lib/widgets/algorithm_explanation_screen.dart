import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/utils/theme_provider.dart';

class AlgorithmExplanationScreen extends StatelessWidget {
  const AlgorithmExplanationScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    final colors = isDarkMode ? _DarkColors() : _LightColors();

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: AppBar(
        title: Text('Our Algorithm', style: TextStyle(color: colors.textColor)),
        backgroundColor: colors.backgroundColor,
        iconTheme: IconThemeData(color: colors.textColor),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Content Moderation Section
            _buildSection(
              colors: colors,
              icon: Icons.security,
              title: 'Content Safety First',
              children: [
                Text(
                  '• Any post containing inappropriate content such as sexual, dangerous, or harmful material is removed immediately',
                  style: TextStyle(color: colors.textColor, height: 1.5),
                ),
                SizedBox(height: 8),
                Text(
                  '• Users who violate our content guidelines receive a lifetime ban',
                  style: TextStyle(color: colors.textColor, height: 1.5),
                ),
                SizedBox(height: 8),
                Text(
                  '• All posts go through automated and manual moderation checks',
                  style: TextStyle(color: colors.textColor, height: 1.5),
                ),
              ],
            ),

            SizedBox(height: 24),

            // How Posts Stay Visible Section - MOVED UP
            _buildSection(
              colors: colors,
              icon: Icons.visibility,
              title: 'How Posts Stay Visible',
              children: [
                Text(
                  'To ensure quality content, posts need engagement proportional to their views:',
                  style: TextStyle(color: colors.textColor, height: 1.5),
                ),
                SizedBox(height: 16),
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(0.4),
                    1: FlexColumnWidth(0.6),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                color: colors.textColor.withOpacity(0.2))),
                      ),
                      children: [
                        Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Views',
                            style: TextStyle(
                              color: colors.textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Ratings Required',
                            style: TextStyle(
                              color: colors.textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    _buildTableRow(colors, '30+', '2+ ratings'),
                    _buildTableRow(colors, '100+', '4+ ratings'),
                    _buildTableRow(colors, '250+', '7+ ratings'),
                    _buildTableRow(colors, '500+', '11+ ratings'),
                  ],
                ),
                SizedBox(height: 12),
                Text(
                  'Note: Only ratings from other users count - your own ratings don\'t affect visibility',
                  style: TextStyle(
                    color: colors.textColor.withOpacity(0.8),
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),

            SizedBox(height: 24),

            // Recommendation System Section - MOVED DOWN
            _buildSection(
              colors: colors,
              icon: Icons.group,
              title: 'Recommendation System',
              children: [
                Text(
                  'We use an advanced collaborative filtering algorithm that learns from user preferences:',
                  style: TextStyle(color: colors.textColor, height: 1.5),
                ),
                SizedBox(height: 16),
                Column(
                  children: [
                    _buildAlgorithmCard(
                      colors: colors,
                      number: '1',
                      title: 'Personalized Recommendations',
                      description:
                          'We analyze ratings from users with similar tastes to suggest posts you might like',
                    ),
                    SizedBox(height: 12),
                    _buildAlgorithmCard(
                      colors: colors,
                      number: '2',
                      title: 'Quality Engagement',
                      description:
                          'Posts need genuine user ratings (excluding the owner) to stay visible in feeds',
                    ),
                    SizedBox(height: 12),
                    _buildAlgorithmCard(
                      colors: colors,
                      number: '3',
                      title: 'Progressive Visibility',
                      description:
                          'As posts get more views, they need proportional engagement to remain visible',
                    ),
                  ],
                ),
              ],
            ),

            SizedBox(height: 24),

            // Feedback Card - REPLACED Why This Works section
            GestureDetector(
              onTap: () {
                // Navigate to feedback screen - you'll need to import and use your feedback screen
                // Navigator.push(context, MaterialPageRoute(builder: (context) => FeedbackScreen()));
              },
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.textColor.withOpacity(0.1)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.feedback, color: colors.textColor, size: 32),
                    SizedBox(height: 12),
                    Text(
                      'Have feedback?',
                      style: TextStyle(
                        color: colors.textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'We\'d love to hear your thoughts and suggestions to improve Ratedly',
                      textAlign: TextAlign
                          .center, // MOVED this parameter from TextStyle to Text widget
                      style: TextStyle(
                        color: colors.textColor.withOpacity(0.8),
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 12),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: colors.backgroundColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: colors.textColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        'Share Feedback',
                        style: TextStyle(
                          color: colors.textColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required _ColorSet colors,
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.textColor.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.textColor, size: 20),
              SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: colors.textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildAlgorithmCard({
    required _ColorSet colors,
    required String number,
    required String title,
    required String description,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.cardColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.textColor.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: colors.textColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    number,
                    style: TextStyle(
                      color: colors.textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: colors.textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.only(left: 36),
            child: Text(
              description,
              style: TextStyle(
                color: colors.textColor.withOpacity(0.8),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  TableRow _buildTableRow(_ColorSet colors, String views, String requirement) {
    return TableRow(
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: colors.textColor.withOpacity(0.1))),
      ),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            views,
            style: TextStyle(
              color: colors.textColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            requirement,
            style: TextStyle(
              color: colors.textColor.withOpacity(0.9),
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

// Color sets for algorithm screen
class _ColorSet {
  final Color textColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color iconColor;

  _ColorSet({
    required this.textColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.iconColor,
  });
}

class _DarkColors extends _ColorSet {
  _DarkColors()
      : super(
          textColor: const Color(0xFFd9d9d9),
          backgroundColor: const Color(0xFF121212),
          cardColor: const Color(0xFF333333),
          iconColor: const Color(0xFFd9d9d9),
        );
}

class _LightColors extends _ColorSet {
  _LightColors()
      : super(
          textColor: Colors.black,
          backgroundColor: Colors.grey[100]!,
          cardColor: Colors.white,
          iconColor: Colors.grey[700]!,
        );
}

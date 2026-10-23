import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class UserGuide extends StatelessWidget {
  const UserGuide({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'User Guide',
          style: TextStyle(
            fontSize: screenHeight * 0.026,
            fontFamily: 'Inter_Bold',
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: Colors.black,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.fromARGB(255, 225, 246, 204),
              Color.fromARGB(255, 234, 238, 201),
              Color.fromARGB(255, 238, 238, 197),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final articles = [
      {
        'image':
            'https://miro.medium.com/v2/resize:fit:640/format:webp/1*YSRPEX_-kfzdDRWZpAOqtw.png',
        'title': 'A Beginner’s Guide To Hydroponics',
        'snippet':
            'How to design, build and operate a small hydroponics farm from an urban farmers who grows over 800 heads of lettuce a year',
        'link':
            'https://runnerrachel-lee.medium.com/a-beginners-guide-to-hydroponically-growing-lettuce-ef305893109a', // Add your article URL here
      },
      {
        'image':
            'https://proponics.co.uk/cdn/shop/articles/Nutrient-Deficiencies-pH_1080x.png?v=1695324051',
        'title': 'Lettuce Nutrient Monitoring Sheet',
        'snippet':
            'Hydroponic lettuce should be grown with a narrower pH range of 5.5 to 6.0, with an optimal target value of 5.8.',
        'link':
            'https://hortamericas.com/wp-content/uploads/2018/04/e-gro-Nutritional-Factsheet-Lettuce.pdf?srsltid=AfmBOoql856Q5u1JnPRRSp6IQscQN8TaAa1Faf9V1QUDuQnnpwT7nzrJ', // Add your article URL here
      },
      {
        'image':
            'https://agora.uplb.edu.ph/wp-content/uploads/2022/03/3-SNAP-Hydroponics.png',
        'title': 'Adding Nutrients and Adjusting pH',
        'snippet':
            'When growing with hydroponics, ensuring you have the right nutrient mix is essential to both the growth and taste of your plants.',
        'link':
            'https://igworks.com/blogs/hydroponic-tips/adding-nutrients-and-adjusting-ph-in-your-hydroponic-garden?srsltid=AfmBOorMHv-X7cul7P4auZcG-8BBtb8J8tfYa-17hbMCQPOP0uW61BGh', // Add your article URL here
      },
    ];

    return ListView.builder(
      itemCount: articles.length,
      itemBuilder: (context, index) {
        final article = articles[index];
        return _buildArticleCard(
          context,
          imageUrl: article['image']!,
          title: article['title']!,
          snippet: article['snippet']!,
          link: article['link']!,
        );
      },
    );
  }

  Widget _buildArticleCard(
    BuildContext context, {
    required String imageUrl,
    required String title,
    required String snippet,
    required String link,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    void _launchURL() async {
      final Uri uri = Uri.parse(link);
      print('Trying to open URL: $uri');

      try {
        bool launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        print('launchUrl returned: $launched');
        if (!launched) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to open the link')));
        }
      } catch (e, stacktrace) {
        print('Exception caught while launching URL: $e');
        print('Stacktrace: $stacktrace');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error launching the link: $e')));
      }
    }

    return GestureDetector(
      onTap: _launchURL,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: double.infinity,
                height: screenWidth * 0.3,
                child: Image.network(imageUrl, fit: BoxFit.cover),
              ),
            ),
            SizedBox(height: screenHeight * 0.016),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: screenHeight * 0.020,
                fontFamily: 'Inter_Bold',
                color: Colors.black87,
              ),
            ),
            SizedBox(height: screenHeight * 0.008),
            Text(
              snippet,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: screenHeight * 0.016,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

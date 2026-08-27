import 'package:flutter/material.dart';
import '../utils/design_constants.dart';
import '../utils/page_info_helper.dart';
import '../widgets/course_guide_widget.dart';

class CourseGuideScreen extends StatelessWidget {
  const CourseGuideScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppDesign.appBar(
          context,
          title: 'Course Guide',
          actions: [
            PageInfoHelper.infoButton(context, PageInfoHelper.courseGuide)
          ],
        ),
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: CourseGuideWidget(),
        ),
      );
}

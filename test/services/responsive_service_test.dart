import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/services/ui/responsive_service.dart';

void main() {
  test('classifies the width offered to a local pane', () {
    expect(ResponsiveService.getScreenSizeForWidth(390), ScreenSize.mobile);
    expect(ResponsiveService.getScreenSizeForWidth(600), ScreenSize.mobile);
    expect(ResponsiveService.getScreenSizeForWidth(601), ScreenSize.tablet);
    expect(ResponsiveService.getScreenSizeForWidth(900), ScreenSize.tablet);
    expect(ResponsiveService.getScreenSizeForWidth(901), ScreenSize.desktop);
  });
}

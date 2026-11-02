import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/utils/drive_link.dart';

void main() {
  test('folder and file links give the id the crawler uses', () {
    expect(driveIdOf('https://drive.google.com/drive/folders/1AbC-d_9?usp=sharing'), '1AbC-d_9');
    expect(driveIdOf('https://drive.google.com/drive/u/1/folders/1AbC-d_9'), '1AbC-d_9');
    expect(driveIdOf('https://drive.google.com/file/d/1XyZ/view?usp=drive_link'), '1XyZ');
    expect(driveIdOf('https://drive.google.com/open?id=1XyZ'), '1XyZ');
    expect(driveIdOf('  https://drive.google.com/drive/folders/1AbC  '), '1AbC');
  });

  test('the same drive shared twice is recognised', () {
    expect(driveIdOf('https://drive.google.com/drive/folders/1AbC?usp=sharing'),
        driveIdOf('https://drive.google.com/drive/folders/1AbC?usp=drive_link'));
  });

  test('links the sync cannot read are refused with a reason', () {
    expect(driveIdOf('http://drive.google.com/drive/folders/1AbC'), isNull);
    expect(driveIdOf('https://example.com/folders/1AbC'), isNull);
    expect(driveIdOf('https://drive.google.com/drive/my-drive'), isNull);
    expect(driveLinkProblem(''), isNotNull);
    expect(driveLinkProblem('my notes'), contains('not a link'));
    expect(driveLinkProblem('https://onedrive.live.com/x'), contains('Google Drive'));
    expect(driveLinkProblem('https://drive.google.com/drive/my-drive'), contains('folder or file'));
    expect(driveLinkProblem('https://drive.google.com/drive/folders/1AbC'), isNull);
  });
}

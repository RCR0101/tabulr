import 'announcement_flag.dart';
import 'announcement_verification.dart';

class AnnouncementUserState {
  final int? vote;
  final AnnouncementFlag? flag;
  final AnnouncementVerification? verification;

  const AnnouncementUserState({this.vote, this.flag, this.verification});

  AnnouncementUserState copyWith({
    int? Function()? vote,
    AnnouncementFlag? Function()? flag,
    AnnouncementVerification? Function()? verification,
  }) {
    return AnnouncementUserState(
      vote: vote != null ? vote() : this.vote,
      flag: flag != null ? flag() : this.flag,
      verification: verification != null ? verification() : this.verification,
    );
  }
}

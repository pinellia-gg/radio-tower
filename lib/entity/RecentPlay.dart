import 'package:objectbox/objectbox.dart';

import 'RadioStation.dart';

/// 最近播放仅保存关联与时间，电台详情始终以 [RadioStation] 表为准。
@Entity()
class RecentPlay {
  @Id()
  int id = 0;

  @Index()
  String stationuuid = '';

  @Index()
  int playedAt = 0;

  final station = ToOne<RadioStation>();
}

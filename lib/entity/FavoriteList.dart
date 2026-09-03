import 'package:objectbox/objectbox.dart';

@Entity()
class FavoriteList {
  @Id()
  int id = 0;

  @Index()
  String name = "";

  @Index()
  bool isDefault = false;

  int createdAt = 0;
  int updatedAt = 0;

  FavoriteList({
    this.name = "",
    this.isDefault = false,
    int? createdAt,
    int? updatedAt,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    this.createdAt = createdAt ?? now;
    this.updatedAt = updatedAt ?? now;
  }
}

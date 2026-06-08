import 'package:iboard_app/models/ad_model.dart';

bool areCarouselAdListsEqual(List<AdModel> first, List<AdModel> second) {
  if (first.length != second.length) return false;
  for (int i = 0; i < first.length; i++) {
    if (!areCarouselAdsEqual(first[i], second[i])) return false;
  }
  return true;
}

bool areCarouselAdsEqual(AdModel first, AdModel second) {
  return first.id == second.id &&
      first.updatedAt == second.updatedAt &&
      first.title == second.title &&
      first.description == second.description &&
      first.type == second.type &&
      first.status == second.status &&
      first.duration == second.duration &&
      first.priority == second.priority &&
      first.startTime == second.startTime &&
      first.endTime == second.endTime &&
      first.display == second.display &&
      first.fileId == second.fileId &&
      first.file.url == second.file.url &&
      first.file.mimeType == second.file.mimeType &&
      first.file.md5 == second.file.md5 &&
      first.file.fileSize == second.file.fileSize &&
      first.isPublic == second.isPublic;
}

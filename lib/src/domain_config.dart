import 'package:domain_manager/src/domain_type.dart';

/// 域名配置信息
class DomainConfig {
  /// 域名配置信息
  const DomainConfig({
    required this.type,
    required this.currentDomain,
    required this.backupDomains,
  });

  /// 1-activity、2-member、3-launch 4-其他
  final DomainType type;

  /// 当前域名
  final String currentDomain;

  /// 备用域名
  final List<String> backupDomains;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DomainConfig &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          currentDomain == other.currentDomain &&
          backupDomains == other.backupDomains);

  @override
  int get hashCode =>
      type.hashCode ^ currentDomain.hashCode ^ backupDomains.hashCode;

  @override
  String toString() {
    return 'DomainConfig{ id: $type, currentDomain: $currentDomain, backupDomains: $backupDomains,}';
  }

  DomainConfig copyWith({
    String? currentDomain,
    List<String>? backupDomains,
  }) {
    return DomainConfig(
      type: type,
      currentDomain: currentDomain ?? this.currentDomain,
      backupDomains: backupDomains ?? this.backupDomains,
    );
  }
}

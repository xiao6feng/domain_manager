import 'package:dio/dio.dart';
import 'package:domain_manager/src/domain_interceptor.dart';
import 'package:domain_manager/src/domain_type.dart';

const String DOMAIN_TYPE = 'domain_type';

/// 添加域名标签拦截器
class DomainTypeInterceptor extends Interceptor {
  /// 添加域名标签拦截器
  const DomainTypeInterceptor({
    required this.type,
    required this.manager,
  });

  /// 域名类型
  final DomainType type;

  /// 域名管理器
  final DomainManager manager;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    super.onRequest(options, handler);
    options.extra.putIfAbsent(DOMAIN_TYPE, () => type.name);
    final newUrl = switch (type) {
      DomainType.cgw => manager.cgwConfig.currentDomain,
      DomainType.member => manager.memberConfig.currentDomain,
      DomainType.launch => manager.launchConfig.currentDomain,
    };
    handler.next(options.copyWith(baseUrl: newUrl));
  }
}

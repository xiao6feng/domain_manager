import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:domain_manager/src/domain_config.dart';
import 'package:domain_manager/src/domain_type.dart';
import 'package:domain_manager/src/domain_type_interceptor.dart';
import 'package:domain_manager/src/iterable_utils.dart';

/// 域名管理器
abstract class DomainManager {
  /// 域名管理器
  DomainManager({required this.dio});

  /// 重试请求 dio
  final Dio dio;
  DomainConfig cgwConfig = const DomainConfig(
    type: DomainType.cgw,
    currentDomain: '',
    backupDomains: [],
  );
  DomainConfig memberConfig = const DomainConfig(
    type: DomainType.member,
    currentDomain: '',
    backupDomains: [],
  );
  DomainConfig launchConfig = const DomainConfig(
    type: DomainType.launch,
    currentDomain: '',
    backupDomains: [],
  );

  final Set<String> _invalidDomains = {};

  /// 自定义配置化
  Future<void> initConfig();

  void _updateDomain(
    DomainType type,
    String domain,
  ) {
    switch (type) {
      case DomainType.cgw:
        cgwConfig.copyWith(currentDomain: domain);
      case DomainType.member:
        memberConfig.copyWith(currentDomain: domain);
      case DomainType.launch:
        launchConfig.copyWith(currentDomain: domain);
    }
  }

  /// 刷新域名配置信息
  void refreshDomainConfig(DomainType type);

  /// 切换域名时强制接口串行切换 典型场景为登录接口 异步并行会导致token失效
  bool forceQueuedRetry(String url) => false;

  void _collectInvalidDomain(String domain) {
    final url = Uri.parse(domain);
    _invalidDomains.add(url.origin);
  }

  List<String> _getBackupDomains(DomainType type) {
    final result = switch (type) {
      DomainType.cgw => cgwConfig.backupDomains,
      DomainType.launch => launchConfig.backupDomains,
      DomainType.member => memberConfig.backupDomains,
    };
    final filterResult = result - _invalidDomains;
    if (filterResult.isEmpty) {
      _invalidDomains.clear();
      return _getBackupDomains(type);
    }
    return filterResult.toList();
  }
}

/// 域名切换拦截器
class DomainInterceptor extends QueuedInterceptor {
  /// 域名切换拦截器
  DomainInterceptor({
    required this.manager,
  });

  /// 域名管理器
  final DomainManager manager;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final domainTypeName = options.extra[DOMAIN_TYPE] as String?;
    if (domainTypeName == null) {
      throw Exception('请检查 dio 是否添加 DomainTypeInterceptor');
    }
    final domainType = DomainType.values
        .firstWhere((element) => element.name == domainTypeName);
    final baseUrl = switch (domainType) {
      DomainType.cgw => manager.cgwConfig.currentDomain,
      DomainType.member => manager.memberConfig.currentDomain,
      DomainType.launch => manager.launchConfig.currentDomain
    };
    handler.next(options.copyWith(baseUrl: baseUrl));
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    if (!err.requestOptions.extra.containsKey('retry')) {
      err.requestOptions.extra
          .putIfAbsent('originUrl', () => err.requestOptions.uri.toString());
    }
    switch (err.type) {
      case DioExceptionType.connectionTimeout ||
            DioExceptionType.connectionError ||
            DioExceptionType.sendTimeout ||
            DioExceptionType.receiveTimeout:
        await _retryRequest(err, handler);
      case DioExceptionType.badResponse:
        final statusCode = err.response?.statusCode ?? 0;
        final serverCode = (err.response?.data as Map?)?['code'];
        switch (statusCode) {
          case 200:
          // 系统维护，不触发域名切换
          case 503 when serverCode == 4091:
            handler.next(err);
          default:
            await _retryRequest(err, handler);
            break;
        }
      case DioExceptionType.unknown:
        switch (err.error) {
          case SocketException || HttpException || FormatException:
            await _retryRequest(err, handler);
          default:
            handler.next(err);
        }
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
        handler.next(err);
    }
  }

  Future<void> _retryRequest(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    manager._collectInvalidDomain(err.requestOptions.baseUrl);

    final domainTypeName = err.requestOptions.extra[DOMAIN_TYPE] as String?;
    if (domainTypeName == null) {
      throw Exception('请检查 dio 是否添加 DomainTypeInterceptor');
    }
    final domainType = DomainType.values
        .firstWhere((element) => element.name == domainTypeName);
    final domains = manager._getBackupDomains(domainType);

    bool isValidResponse(Response<Object?> response) {
      return response.statusCode == 200;
    }

    void updateDomain(Response<Object?> response) {
      final url = Uri.parse(response.requestOptions.uri.toString());
      manager._updateDomain(domainType, url.origin);
    }

    void checkDomain() {
      if (domains.length <= 5) {
        manager.refreshDomainConfig(domainType);
      }
    }

    if (manager.forceQueuedRetry(err.requestOptions.uri.toString())) {
      for (final domain in domains) {
        try {
          err.requestOptions.extra.putIfAbsent('retry', () => true);
          final response = await manager.dio.fetch<Object?>(
            err.requestOptions.copyWith(baseUrl: domain),
          );
          if (isValidResponse(response)) {
            updateDomain(response);
            checkDomain();
            handler.resolve(response);
            return;
          }
        } catch (e) {
          if (e is DioException) {
            manager._collectInvalidDomain(e.requestOptions.uri.toString());
          }
          continue;
        }
      }
    } else {
      final groupDomains = domains
          .windowed(3, step: 3, partialWindows: true)
          .toList(growable: false);
      for (final group in groupDomains) {
        try {
          final response = await _parallelRetry(group, err);
          if (isValidResponse(response)) {
            updateDomain(response);
            checkDomain();
            handler.resolve(response);
            return;
          }
        } catch (e) {
          if (e is DioException) {
            manager._collectInvalidDomain(e.requestOptions.uri.toString());
          }
          continue;
        }
      }
    }
    handler.next(err);
  }

  Future<Response<dynamic>> _parallelRetry(
    List<String> domains,
    DioException err,
  ) async {
    var errorCount = 0;
    final completer = Completer<Response<dynamic>>();
    if (domains.isEmpty) {
      completer.completeError(err);
      return completer.future;
    }

    void handleRetryRequest(String domain) {
      err.requestOptions.extra.putIfAbsent('retry', () => true);
      manager.dio
          .fetch<Object?>(
        err.requestOptions.copyWith(
          baseUrl: domain,
        ),
      )
          .then((value) {
        if (!completer.isCompleted) {
          completer.complete(value);
        }
      }).onError((error, stackTrace) {
        errorCount++;
        if (error is DioException) {
          manager._collectInvalidDomain(error.requestOptions.uri.toString());
        }
        if (!completer.isCompleted && errorCount >= domains.length) {
          completer.completeError(err);
        }
      });
    }

    for (final domain in domains) {
      handleRetryRequest(domain);
    }
    return completer.future;
  }
}

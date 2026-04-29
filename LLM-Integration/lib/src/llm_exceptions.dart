sealed class LlmException implements Exception {
  LlmException(this.message);
  final String message;

  @override
  String toString() => '${runtimeType.toString()}: $message';
}

final class LlmConfigurationException extends LlmException {
  LlmConfigurationException(super.message);
}

final class LlmTransportException extends LlmException {
  LlmTransportException(super.message);
}

final class LlmProviderException extends LlmException {
  LlmProviderException(super.message, {this.statusCode});
  final int? statusCode;
}

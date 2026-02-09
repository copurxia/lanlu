/**
 * ErrorBoundary - React错误边界组件
 */

import React, { Component } from 'react';
import type { ReactNode } from 'react';

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
  onError?: (error: Error, errorInfo: React.ErrorInfo) => void;
}

interface State {
  hasError: boolean;
  error?: Error;
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    console.error('[ErrorBoundary] Caught an error:', error, errorInfo);

    // 调用自定义错误处理
    this.props.onError?.(error, errorInfo);

    // 可以在这里发送错误报告到监控系统
    // 例如：Sentry, LogRocket 等
  }

  render() {
    if (this.state.hasError) {
      // 自定义错误显示
      if (this.props.fallback) {
        return this.props.fallback;
      }

      // 默认错误显示
      return (
        <div className="p-4 text-center">
          <div className="text-red-600 text-sm font-medium mb-2">
            出现了一些问题
          </div>
          <div className="text-xs text-muted-foreground mb-4">
            {this.state.error?.message || '未知错误'}
          </div>
          <button
            onClick={() => window.location.reload()}
            className="text-xs underline underline-offset-2 text-muted-foreground hover:text-foreground"
          >
            刷新页面
          </button>
        </div>
      );
    }

    return this.props.children;
  }
}

/**
 * 创建错误边界的Hook
 */
export function useErrorHandler() {
  return (error: Error, errorInfo?: React.ErrorInfo) => {
    console.error('[useErrorHandler] Error occurred:', error, errorInfo);
    // 这里可以添加全局错误处理逻辑
    // 例如：发送到监控系统
  };
}

/**
 * TaskPoller专用错误边界
 */
interface TaskPollerErrorBoundaryProps {
  children: ReactNode;
}

interface TaskPollerErrorBoundaryState {
  hasError: boolean;
  retryCount: number;
}

export class TaskPollerErrorBoundary extends Component<
  TaskPollerErrorBoundaryProps,
  TaskPollerErrorBoundaryState
> {
  private maxRetries = 3;

  constructor(props: TaskPollerErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, retryCount: 0 };
  }

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  static getDerivedStateFromError(_error: Error): Partial<TaskPollerErrorBoundaryState> {
    return { hasError: true };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    console.error('[TaskPollerErrorBoundary] TaskPoller error:', error, errorInfo);
  }

  handleRetry = () => {
    this.setState((prevState) => ({
      hasError: false,
      retryCount: prevState.retryCount + 1,
    }));
  };

  render() {
    if (this.state.hasError) {
      const canRetry = this.state.retryCount < this.maxRetries;

      return (
        <div className="p-4 text-center border rounded-lg">
          <div className="text-red-600 text-sm font-medium mb-2">
            任务轮询器遇到错误
          </div>
          <div className="text-xs text-muted-foreground mb-4">
            {canRetry
              ? `出现错误，正在尝试重新启动... (${this.state.retryCount}/${this.maxRetries})`
              : '任务轮询器已停止，请刷新页面重试'}
          </div>
          {canRetry && (
            <button
              onClick={this.handleRetry}
              className="text-xs px-3 py-1 bg-primary text-primary-foreground rounded"
            >
              重试
            </button>
          )}
        </div>
      );
    }

    return this.props.children;
  }
}

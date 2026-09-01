import { Component, type ErrorInfo, type ReactNode } from 'react';
import { Button, Result } from 'antd';

import { getAdminErrorNotification } from './error-messages';

type ErrorBoundaryProps = {
  children: ReactNode;
};

type ErrorBoundaryState = {
  hasError: boolean;
  message?: string;
  description?: string;
};

export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  state: ErrorBoundaryState = { hasError: false };

  static getDerivedStateFromError(error: unknown): ErrorBoundaryState {
    const notification = getAdminErrorNotification(error);
    return {
      hasError: true,
      message: notification.message,
      description: notification.description,
    };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    console.error('Admin application error boundary captured an error.', error, info);
  }

  render(): ReactNode {
    if (this.state.hasError) {
      return (
        <Result
          status="error"
          title="Admin console unavailable"
          subTitle={this.state.description ?? 'The page could not be loaded. Try refreshing.'}
          extra={
            <Button type="primary" onClick={() => window.location.reload()}>
              Refresh page
            </Button>
          }
        />
      );
    }

    return this.props.children;
  }
}

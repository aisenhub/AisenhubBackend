import { Component, type ErrorInfo, type ReactNode } from 'react';
import { Button, Result } from 'antd';

type ErrorBoundaryProps = {
  children: ReactNode;
};

type ErrorBoundaryState = {
  hasError: boolean;
};

export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  state: ErrorBoundaryState = { hasError: false };

  static getDerivedStateFromError(): ErrorBoundaryState {
    return { hasError: true };
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
          subTitle="The page could not be loaded. Try refreshing the current session."
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

import type { ThemeConfig } from 'antd';

export const adminTheme: ThemeConfig = {
  token: {
    colorPrimary: '#176b87',
    colorInfo: '#176b87',
    colorSuccess: '#2f7d62',
    colorWarning: '#b7791f',
    colorError: '#b54747',
    colorText: '#19323c',
    colorTextSecondary: '#58717b',
    colorBgLayout: '#f4f7f8',
    colorBgContainer: '#ffffff',
    borderRadius: 10,
    fontFamily:
      'Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
  },
  components: {
    Layout: {
      headerBg: '#102f3b',
      siderBg: '#123b49',
      bodyBg: '#f4f7f8',
    },
    Menu: {
      darkItemBg: '#123b49',
      darkItemSelectedBg: '#176b87',
      darkItemHoverBg: '#1a5060',
    },
    Card: {
      headerFontSize: 16,
    },
  },
};

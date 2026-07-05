import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.yuesheng.writingcoach',
  appName: '月笙写作教练',
  webDir: 'dist/renderer',
  plugins: {
    CapacitorSQLite: {
      iosDatabaseLocation: 'Library/CapacitorDatabase',
      androidDatabaseLocation: 'databases',
    },
  },
};

export default config;

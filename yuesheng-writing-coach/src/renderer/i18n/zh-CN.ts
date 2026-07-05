/**
 * 中文（简体）翻译 — i18n 基础配置
 *
 * 使用 react-intl 的 defineMessages 模式。
 * 当前为初始迁移起点，后续逐步将各组件的硬编码文本迁移至此。
 *
 * 使用方式:
 *   import { useIntl } from 'react-intl';
 *   const { formatMessage } = useIntl();
 *   <h1>{formatMessage({ id: 'app.title' })}</h1>
 *
 * 命名规范: domain.component.element
 */
const zhCN: Record<string, string> = {
  // 全局
  'app.title': '月笙写作教练',
  'app.loading': '加载中...',
  'app.error': '出错了',
  'app.retry': '重试',
  'app.save': '保存',
  'app.cancel': '取消',
  'app.confirm': '确认',
  'app.back': '返回',
  'app.close': '关闭',

  // TabBar
  'tab.bookshelf': '书架',
  'tab.chat': '对话',
  'tab.trainingPlan': '训练计划',
  'tab.growth': '成长',
  'tab.settings': '设置',

  // ChatPage
  'chat.title': '对话',
  'chat.input.placeholder': '输入消息...',
  'chat.welcome.greeting': '嘿，今天想从哪里开始？',
  'chat.welcome.analyzeWork': '分析一下作品',
  'chat.welcome.learnTechnique': '学点描写技法',
  'chat.welcome.practice': '出个题目练练',

  // Training Flow
  'training.flow.step1': '解说技法',
  'training.flow.step2': '例证展示',
  'training.flow.step3': '确认理解',
  'training.flow.step4': '尝试改写',
  'training.flow.step5': '获得反馈',
  'training.flow.previous': '上一步',
  'training.flow.next': '下一步',
  'training.flow.submit': '提交评估',
  'training.flow.returnToChat': '返回对话',
  'training.flow.evaluating': '评估中...',

  // System Message
  'system.diagnosis.found': '已识别 {count} 个写作症候',
  'system.training.detected': '检测到「{name}」症候，建议进行专项训练',
  'system.phase.transition': '进入{phase}阶段',
};

export default zhCN;

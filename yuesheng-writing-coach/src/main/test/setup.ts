/**
 * 主进程测试全局 setup
 * 在运行所有 main 测试前初始化全局依赖
 */
import { TechniqueLibraryLoader } from '../shared/services/technique-loader';
import * as path from 'path';

// 技法库初始化为 resources/config/technique-library.json
// 测试时从 src/main/test/setup.ts 到 resources 的路径
const techniquePath = path.join(__dirname, '..', '..', '..', 'resources', 'config', 'technique-library.json');
TechniqueLibraryLoader.init(techniquePath);

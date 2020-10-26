import ReactDOM from 'react-dom';
// @ts-ignore
import { plugin, ApplyPluginsType, setCreateHistoryOptions, history } from 'umi';
// @ts-ignore
import { createHistory } from '@@/core/history';
// @ts-ignore
import { setModelState } from './qiankunModel';

const noop = () => {};

type Defer = {
  promise: Promise<any>;
  resolve(value?: any): void;
};

// @ts-ignore
const defer: Defer = {};
defer.promise = new Promise(resolve => {
  defer.resolve = resolve;
});

let render = noop;
let hasMountedAtLeastOnce = false;

export default () => defer.promise;
export const clientRenderOptsStack: any[] = [];

function normalizeHistory(
  history?: 'string' | Record<string, any>,
  base?: string,
) {
  let normalizedHistory: Record<string, any> = {};
  if (base) normalizedHistory.basename = base;
  if (history) {
    if (typeof history === 'string') {
      normalizedHistory.type = history;
    } else {
      normalizedHistory = history;
    }
  }

  return normalizedHistory;
}

function getSlaveRuntime() {
  const config = plugin.applyPlugins({
    key: 'qiankun',
    type: ApplyPluginsType.modify,
    initialValue: {},
  });
  // 应用既是 master 又是 slave 的场景，运行时 slave 配置方式为 export const qiankun = { slave: {} }
  const { slave } = config;
  return slave || config;
}

export function genBootstrap(oldRender: typeof noop) {
  return async (props: any) => {
    const slaveRuntime = getSlaveRuntime();
    if (slaveRuntime.bootstrap) {
      await slaveRuntime.bootstrap(props);
    }
    render = oldRender;
  };
}

export function genMount(mountElementId: string) {
  return async (props?: any) => {
    // props 有值时说明应用是通过 lifecycle 被主应用唤醒的，而不是独立运行时自己 mount
    if (typeof props !== 'undefined') {
      setModelState(props);

      const slaveRuntime = getSlaveRuntime();
      if (slaveRuntime.mount) {
        await slaveRuntime.mount(props);
      }

      // 动态改变 history
      const historyOptions = normalizeHistory(props?.history, props?.base);
      setCreateHistoryOptions(historyOptions);

      // 更新 clientRender 配置
      const clientRenderOpts = {
        // 默认开启
        // 如果需要手动控制 loading，通过主应用配置 props.autoSetLoading false 可以关闭
        callback: () => {
          if (props?.autoSetLoading && typeof props?.setLoading === 'function') {
            props.setLoading(false);
          }

          // 支持将子应用的 history 回传给父应用
          if (typeof props?.onHistoryInit === 'function') {
            props.onHistoryInit(history);
          }
        },
        // 支持通过 props 注入 container 来限定子应用 mountElementId 的查找范围
        // 避免多个子应用出现在同一主应用时出现 mount 冲突
        rootElement:
          props?.container?.querySelector(`#${mountElementId}`) || mountElementId,
        // FIXME 子应用嵌入模式下不支持热更
        history: createHistory(),
      };

      clientRenderOptsStack.push(clientRenderOpts);
    }

    // 第一次 mount defer 被 resolve 后umi 会自动触发 render，非第一次 mount 则需手动触发
    if (hasMountedAtLeastOnce) {
      render();
    } else {
      defer.resolve();
    }

    hasMountedAtLeastOnce = true;
  };
}

export function genUpdate() {
  return async (props: any) => {
    setModelState(props);

    const slaveRuntime = getSlaveRuntime();
    if (slaveRuntime.update) {
      await slaveRuntime.update(props);
    }
  };
}

export function genUnmount(mountElementId: string) {
  return async (props: any) => {
    const container = props?.container
      ? props.container.querySelector(`#${mountElementId}`)
      : document.getElementById(mountElementId);
    if (container) {
      ReactDOM.unmountComponentAtNode(container);
    }

    const slaveRuntime = getSlaveRuntime();
    if (slaveRuntime.unmount) await slaveRuntime.unmount(props);
  };
}

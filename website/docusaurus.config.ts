import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';
import {themes as prismThemes} from 'prism-react-renderer';

const config: Config = {
  title: 'MemontoMori',
  tagline: 'macOS メニューバー常駐のメモ＆ローテーション表示アプリ',
  favicon: 'img/favicon.png',

  // GitHub Pages 用。リポジトリ名に合わせている。
  url: 'https://kimi8-lapi16.github.io',
  baseUrl: '/MemontoMori/',
  organizationName: 'kimi8-lapi16',
  projectName: 'MemontoMori',
  trailingSlash: false,

  onBrokenLinks: 'throw',

  i18n: {
    defaultLocale: 'ja',
    locales: ['ja'],
  },

  markdown: {
    mermaid: true,
    hooks: {
      onBrokenMarkdownLinks: 'warn',
    },
  },
  themes: ['@docusaurus/theme-mermaid'],

  presets: [
    [
      'classic',
      {
        docs: {
          // ドキュメント本体はリポジトリ直下の docs/ を参照する。
          path: '../docs',
          routeBasePath: '/',
          sidebarPath: './sidebars.ts',
          editUrl:
            'https://github.com/kimi8-lapi16/MemontoMori/tree/master/',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    image: 'img/logo.png',
    colorMode: {
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'MemontoMori',
      logo: {
        alt: 'MemontoMori logo',
        src: 'img/logo.png',
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'docsSidebar',
          position: 'left',
          label: 'ドキュメント',
        },
        {
          href: 'https://github.com/kimi8-lapi16/MemontoMori',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'ドキュメント',
          items: [
            {label: 'はじめに', to: '/'},
            {label: 'アーキテクチャ', to: '/architecture'},
            {label: 'ビルド & リリース', to: '/development/build-and-release'},
          ],
        },
        {
          title: 'リンク',
          items: [
            {
              label: 'GitHub',
              href: 'https://github.com/kimi8-lapi16/MemontoMori',
            },
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} MemontoMori. Built with Docusaurus.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['swift', 'bash', 'yaml', 'json'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;

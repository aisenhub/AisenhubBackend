import { Descriptions, Tag } from 'antd';

export type ProductVersionDiffProps = {
  readonly currentVersion: number | null;
  readonly publishedVersion: number | null;
};

export function ProductVersionDiff({ currentVersion, publishedVersion }: ProductVersionDiffProps) {
  const aligned = currentVersion !== null && currentVersion === publishedVersion;
  return (
    <Descriptions column={1} size="small" bordered>
      <Descriptions.Item label="Current pointer">
        {currentVersion ? `v${currentVersion}` : 'Not selected'}
      </Descriptions.Item>
      <Descriptions.Item label="Latest published">
        {publishedVersion ? `v${publishedVersion}` : 'None'}
      </Descriptions.Item>
      <Descriptions.Item label="State">
        <Tag color={aligned ? 'green' : 'gold'}>{aligned ? 'Aligned' : 'Review required'}</Tag>
      </Descriptions.Item>
    </Descriptions>
  );
}

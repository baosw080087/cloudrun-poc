#!/bin/bash
set -e

ACTION=$1
SERVICE_NAME="my-go-app"
REGION="asia-northeast1"

if [ "$ACTION" == "deploy" ]; then
    echo "🚀 正在部署预览版 (Preview)..."
    # 部署新版本，分配 0% 流量，并打上 preview 标签
    gcloud run deploy $SERVICE_NAME \
        --source . \
        --region $REGION \
        --no-traffic \
        --tag preview \
        --set-labels=stage=preview

    # 获取预览 URL 供测试人员使用
    PREVIEW_URL=$(gcloud run services describe $SERVICE_NAME --region $REGION --format='value(status.traffic[1].url)')
    echo "✅ 预览版部署完成！"
    echo "🔗 测试地址: $PREVIEW_URL"

elif [ "$ACTION" == "promote" ]; then
    echo "🎉 正在全量发布 (Promote)..."
    # 1. 将流量 100% 切给带 preview 标签的版本
    gcloud run services update-traffic $SERVICE_NAME --region $REGION --to-tags preview=100
    
    # 2. 重新整理标签：将现在的版本标为 stable，移除 preview 标签
    # 获取当前最新的修订版本
    LATEST_REV=$(gcloud run revisions list --service $SERVICE_NAME --region $REGION --limit 1 --format="value(name)")
    
    gcloud run services update-traffic $SERVICE_NAME --region $REGION --set-tags stable=$LATEST_REV
    gcloud run services update-traffic $SERVICE_NAME --region $REGION --remove-tags preview
    echo "✅ 全量发布完成！域名 my-test.jhc-dts.com 现在指向新版本。"

elif [ "$ACTION" == "abort" ]; then
    echo "⚠️ 正在中止并回滚 (Abort)..."
    # 1. 强制将流量切回 stable 标签
    gcloud run services update-traffic $SERVICE_NAME --region $REGION --to-tags stable=100
    # 2. 移除 preview 标签
    gcloud run services update-traffic $SERVICE_NAME --region $REGION --remove-tags preview
    echo "✅ 已回滚。my-test.jhc-dts.com 安全指向旧版本。"
fi
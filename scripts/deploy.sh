#!/bin/bash
set -e

# 从输入参数获取动作，默认为 deploy
ACTION=${1:-"deploy"}
SERVICE_NAME="my-go-app"
REGION="asia-northeast1"

# 检查服务是否存在
# 使用 --quiet 确保在 CI 环境下不产生交互
echo "🔍 检查服务 $SERVICE_NAME 状态..."
SERVICE_EXISTS=$(gcloud run services list --filter="SERVICE:$SERVICE_NAME" --format="value(SERVICE)" --region $REGION --quiet || echo "")

if [ "$ACTION" == "deploy" ]; then
    if [ -z "$SERVICE_EXISTS" ]; then
        echo "🆕 检测到服务不存在，正在执行首次部署 (Initial Deploy)..."
        # 首次部署不能使用 --no-traffic，且必须分配流量
        gcloud run deploy $SERVICE_NAME \
            --source . \
            --region $REGION \
            --allow-unauthenticated \
            --quiet \
            --set-tags stable=LATEST \
            --update-labels=stage=stable
        
        echo "✅ 首次部署成功！服务已上线。"
    else
        echo "🚀 正在部署预览版 (Preview)..."
        # 非首次部署，使用 --no-traffic 实现蓝绿部署
        # 修正了之前报错的 --update-labels
        gcloud run deploy $SERVICE_NAME \
            --source . \
            --region $REGION \
            --no-traffic \
            --tag preview \
            --update-labels=stage=preview \
            --quiet

        # 获取预览 URL (通常预览版在 traffic 数组的末尾或特定索引)
        PREVIEW_URL=$(gcloud run services describe $SERVICE_NAME --region $REGION --format='value(status.traffic[?(@.tag=="preview")].url)')
        echo "✅ 预览版部署完成！"
        echo "🔗 测试地址: $PREVIEW_URL"
    fi

elif [ "$ACTION" == "promote" ]; then
    if [ -z "$SERVICE_EXISTS" ]; then
        echo "❌ 错误：服务不存在，无法执行 Promote。"
        exit 1
    fi
    echo "🎉 正在全量发布 (Promote)..."
    # 1. 将流量 100% 切给带 preview 标签的版本
    gcloud run services update-traffic $SERVICE_NAME --region $REGION --to-tags preview=100 --quiet
    
    # 2. 重新整理标签：将现在的版本标为 stable，移除 preview 标签
    LATEST_REV=$(gcloud run revisions list --service $SERVICE_NAME --region $REGION --limit 1 --format="value(name)" --quiet)
    
    gcloud run services update-traffic $SERVICE_NAME --region $REGION --set-tags stable=$LATEST_REV --quiet
    gcloud run services update-traffic $SERVICE_NAME --region $REGION --remove-tags preview --quiet
    echo "✅ 全量发布完成！生产流量现在指向新版本。"

elif [ "$ACTION" == "abort" ]; then
    echo "⚠️ 正在中止并回滚 (Abort)..."
    # 确保 stable 标签存在并承接所有流量
    gcloud run services update-traffic $SERVICE_NAME --region $REGION --to-tags stable=100 --quiet
    gcloud run services update-traffic $SERVICE_NAME --region $REGION --remove-tags preview --quiet
    echo "✅ 已回滚。流量安全指向旧版 (stable)。"
fi
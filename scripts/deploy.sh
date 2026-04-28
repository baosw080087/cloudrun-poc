#!/bin/bash
set -e

# 参数处理：默认为 deploy，支持 promote 和 abort
ACTION=${1:-"deploy"}
SERVICE_NAME="my-go-app"
REGION="asia-northeast1"

echo "🔍 正在检查服务 $SERVICE_NAME 在 $REGION 的状态..."

# 1. 检查服务是否存在 (增加 --quiet 并在失败时返回空字符串)
SERVICE_EXISTS=$(gcloud run services list --filter="SERVICE:$SERVICE_NAME" --format="value(SERVICE)" --region $REGION --quiet || echo "")

if [ "$ACTION" == "deploy" ]; then
    if [ -z "$SERVICE_EXISTS" ]; then
        echo "🆕 检测到服务不存在，正在执行【首次全量部署】..."
        # 首次部署：不能带 --no-traffic，必须分配 100% 流量
        # 加上 --quiet 自动处理 Artifact Registry 创建和 Allow Unauthenticated 确认
        gcloud run deploy $SERVICE_NAME \
            --source . \
            --region $REGION \
            --allow-unauthenticated \
            --set-tags stable=LATEST \
            --update-labels=stage=stable \
            --quiet
        echo "✅ 首次部署成功！服务已分配 stable 标签并上线。"
    else
        echo "🚀 服务已存在，正在部署【预览版 (Preview)】..."
        # 蓝绿发布逻辑：不切换流量，打上 preview 标签
        gcloud run deploy $SERVICE_NAME \
            --source . \
            --region $REGION \
            --no-traffic \
            --tag preview \
            --update-labels=stage=preview \
            --quiet

        # 精确获取预览版专用测试 URL
        PREVIEW_URL=$(gcloud run services describe $SERVICE_NAME --region $REGION --format='value(status.traffic[?(@.tag=="preview")].url)')
        echo "✅ 预览版部署完成！"
        echo "🔗 预览地址: $PREVIEW_URL"
    fi

elif [ "$ACTION" == "promote" ]; then
    echo "🎉 正在执行【全量发布 (Promote)】..."
    # 1. 将 100% 流量切给 preview 标签版本
    gcloud run services update-traffic $SERVICE_NAME --region $REGION --to-tags preview=100 --quiet
    
    # 2. 标签重置：将当前版本转为 stable，移除 preview 标签
    LATEST_REV=$(gcloud run revisions list --service $SERVICE_NAME --region $REGION --limit 1 --format="value(name)" --quiet)
    
    gcloud run services update-traffic $SERVICE_NAME --region $REGION --set-tags stable=$LATEST_REV --quiet
    gcloud run services update-traffic $SERVICE_NAME --region $REGION --remove-tags preview --quiet
    echo "✅ 发布完成！生产流量已指向新版本。"

elif [ "$ACTION" == "abort" ]; then
    echo "⚠️ 正在执行【紧急回滚 (Abort)】..."
    # 强制将流量切回 stable 标签
    gcloud run services update-traffic $SERVICE_NAME --region $REGION --to-tags stable=100 --quiet
    # 清理 preview 标签
    gcloud run services update-traffic $SERVICE_NAME --region $REGION --remove-tags preview --quiet
    echo "✅ 已回退。流量安全保留在旧版 (stable) 环境。"
fi
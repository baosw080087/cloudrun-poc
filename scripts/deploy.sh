#!/bin/bash
set -e

# 参数处理：默认为 deploy，支持 promote 和 abort
ACTION=${1:-"deploy"}
SERVICE_NAME="my-go-app-blue"
REGION="asia-northeast1"

echo "🔍 正在检查服务 $SERVICE_NAME 在 $REGION 的状态..."

# 1. 极其严格的检查服务是否存在逻辑
# 2>/dev/null 屏蔽所有警告，grep -w 确保精确匹配名字，防止误判
SERVICE_CHECK=$(gcloud run services list --filter="SERVICE:$SERVICE_NAME" --format="value(SERVICE)" --region $REGION --quiet 2>/dev/null | grep -w "$SERVICE_NAME" || true)

if [ "$ACTION" == "deploy" ]; then
    if [ -z "$SERVICE_CHECK" ]; then
        echo "🆕 [ACTION: INITIAL] 检测到服务完全不存在。正在执行首次全量部署..."
        
        # 首次部署：绝对不能带 --no-traffic
        gcloud run deploy $SERVICE_NAME \
            --source . \
            --region $REGION \
            --allow-unauthenticated \
            --set-tags stable=LATEST \
            --update-labels=stage=stable \
            --quiet
        
        echo "✅ 首次部署成功！服务已上线并分配 stable 标签。"
    else
        echo "🚀 [ACTION: BLUE-GREEN] 服务已存在。正在部署预览版 (Preview)，不切换流量..."
        
        # 蓝绿发布逻辑：使用 --no-traffic
        gcloud run deploy $SERVICE_NAME \
            --source . \
            --region $REGION \
            --no-traffic \
            --tag preview \
            --update-labels=stage=preview \
            --quiet

        # 获取预览测试 URL
        PREVIEW_URL=$(gcloud run services describe $SERVICE_NAME --region $REGION --format='value(status.traffic[?(@.tag=="preview")].url)')
        echo "✅ 预览版部署完成！"
        echo "🔗 预览测试地址: $PREVIEW_URL"
    fi

elif [ "$ACTION" == "promote" ]; then
    echo "🎉 [ACTION: PROMOTE] 正在执行全量发布，将流量切向新版本..."
    
    # 1. 将 100% 流量切给带 preview 标签的版本
    gcloud run services update-traffic $SERVICE_NAME --region $REGION --to-tags preview=100 --quiet
    
    # 2. 重新整理标签：将现在的版本标为 stable，移除 preview 标签
    LATEST_REV=$(gcloud run revisions list --service $SERVICE_NAME --region $REGION --limit 1 --format="value(name)" --quiet)
    
    gcloud run services update-traffic $SERVICE_NAME --region $REGION --set-tags stable=$LATEST_REV --quiet
    gcloud run services update-traffic $SERVICE_NAME --region $REGION --remove-tags preview --quiet
    
    echo "✅ 发布完成！生产流量现在指向新版本。"

elif [ "$ACTION" == "abort" ]; then
    echo "⚠️ [ACTION: ABORT] 正在执行紧急回滚..."
    
    # 强制将流量全部切回带有 stable 标签的旧版本
    gcloud run services update-traffic $SERVICE_NAME --region $REGION --to-tags stable=100 --quiet
    
    # 清理掉失败的 preview 标签
    gcloud run services update-traffic $SERVICE_NAME --region $REGION --remove-tags preview --quiet
    
    echo "✅ 已回退。流量安全保留在旧版 (stable) 环境。"
fi
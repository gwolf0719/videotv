#!/bin/bash

# VideoTV APK 發布工具
# 作者: VideoTV Team
# 用途: 自動更新版本號並建構發布版本的 APK

set -e  # 遇到錯誤時立即退出

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# 配置
APK_OUTPUT_DIR="releases"

# 輔助函數
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header() {
    echo -e "${PURPLE}$1${NC}"
}

# 創建發布目錄
create_release_dir() {
    if [ ! -d "$APK_OUTPUT_DIR" ]; then
        mkdir -p "$APK_OUTPUT_DIR"
        print_info "已創建發布目錄: $APK_OUTPUT_DIR"
    fi
}

# 檢查 Flutter
check_flutter() {
    print_info "檢查 Flutter 環境..."
    
    if ! command -v flutter &> /dev/null; then
        print_error "Flutter 未安裝或不在 PATH 中"
        exit 1
    fi
    
    # 檢查 Flutter 版本
    local flutter_version=$(flutter --version | head -n 1)
    print_info "Flutter 版本: $flutter_version"
    
    # 檢查 Flutter 項目健康度
    print_info "檢查項目依賴..."
    flutter doctor > /dev/null 2>&1 || print_warning "Flutter doctor 檢查發現問題，但繼續執行"
    
    print_success "Flutter 環境檢查完成"
}

# 獲取當前版本
get_current_version() {
    local version_line=$(grep "^version:" pubspec.yaml)
    echo "$version_line" | sed 's/version: //' | tr -d ' '
}

# 解析版本號
parse_version() {
    local version=$1
    local version_name=$(echo "$version" | cut -d'+' -f1)
    local build_number=$(echo "$version" | cut -d'+' -f2)
    
    local major=$(echo "$version_name" | cut -d'.' -f1)
    local minor=$(echo "$version_name" | cut -d'.' -f2)
    local patch=$(echo "$version_name" | cut -d'.' -f3)
    
    echo "$major $minor $patch $build_number"
}

# 自動更新版本號
auto_increment_version() {
    local current_version=$(get_current_version)
    print_info "當前版本: $current_version"
    
    local version_parts=($(parse_version "$current_version"))
    local major=${version_parts[0]}
    local minor=${version_parts[1]}
    local patch=${version_parts[2]}
    local build=${version_parts[3]}
    
    # 自動增加建構號
    build=$((build + 1))
    local new_version="$major.$minor.$patch+$build"
    
    print_info "新版本: $new_version"
    
    # 更新 pubspec.yaml
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/^version:.*/version: $new_version/" pubspec.yaml
    else
        # Linux
        sed -i "s/^version:.*/version: $new_version/" pubspec.yaml
    fi
    
    print_success "版本號已更新為: $new_version"
    echo "$new_version"
}

# 手動設定版本號
manual_set_version() {
    local current_version=$(get_current_version)
    print_info "當前版本: $current_version"
    
    echo ""
    print_header "版本更新選項："
    echo "1) 補丁版本 (1.0.0 -> 1.0.1) - 修復 bug"
    echo "2) 次要版本 (1.0.0 -> 1.1.0) - 新功能"
    echo "3) 主要版本 (1.0.0 -> 2.0.0) - 重大變更"
    echo "4) 建構號   (1.0.0+1 -> 1.0.0+2) - 測試版本"
    echo ""
    read -p "請選擇版本更新類型 [1-4]: " version_type
    
    local version_parts=($(parse_version "$current_version"))
    local major=${version_parts[0]}
    local minor=${version_parts[1]}
    local patch=${version_parts[2]}
    local build=${version_parts[3]}
    
    case $version_type in
        1)
            patch=$((patch + 1))
            build=$((build + 1))
            print_info "更新補丁版本"
            ;;
        2)
            minor=$((minor + 1))
            patch=0
            build=$((build + 1))
            print_info "更新次要版本"
            ;;
        3)
            major=$((major + 1))
            minor=0
            patch=0
            build=$((build + 1))
            print_info "更新主要版本"
            ;;
        4)
            build=$((build + 1))
            print_info "更新建構號"
            ;;
        *)
            print_error "無效的選擇"
            exit 1
            ;;
    esac
    
    local new_version="$major.$minor.$patch+$build"
    print_info "新版本: $new_version"
    
    # 更新 pubspec.yaml
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/^version:.*/version: $new_version/" pubspec.yaml
    else
        # Linux
        sed -i "s/^version:.*/version: $new_version/" pubspec.yaml
    fi
    
    print_success "版本號已更新為: $new_version"
    echo "$new_version"
}

# 清理建構快取
clean_build() {
    print_info "清理建構快取..."
    flutter clean > /dev/null 2>&1
    flutter pub get > /dev/null 2>&1
    print_success "建構快取清理完成"
}

# 建構 APK
build_apk() {
    local version=$1
    print_info "開始建構 APK (版本: $version)..."
    
    create_release_dir
    
    # 建構發布版本 APK
    print_info "建構發布版本 APK..."
    flutter build apk --release
    
    if [ $? -eq 0 ]; then
        # 複製 APK 到發布目錄
        local output_apk="$APK_OUTPUT_DIR/videotv.apk"
        cp build/app/outputs/flutter-apk/app-release.apk "$output_apk"
        
        # 顯示檔案資訊
        local file_size=$(du -h "$output_apk" | cut -f1)
        print_success "APK 建構完成: $output_apk"
        print_info "檔案大小: $file_size"
        
        # 開啟檔案管理器顯示檔案位置
        if [[ "$OSTYPE" == "darwin"* ]]; then
            open -R "$output_apk"
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            xdg-open "$APK_OUTPUT_DIR"
        fi
        
        return 0
    else
        print_error "APK 建構失敗"
        return 1
    fi
}

# 顯示使用說明
show_usage() {
    echo "VideoTV APK 發布工具使用方法："
    echo ""
    echo "  ./upload.sh          # 手動選擇版本更新類型"
    echo "  ./upload.sh --auto   # 自動增加建構號"
    echo "  ./upload.sh --help   # 顯示此說明"
    echo ""
    echo "功能："
    echo "  - 自動更新 pubspec.yaml 中的版本號"
    echo "  - 清理並重新建構 Flutter APK"
    echo "  - 輸出到 releases/ 目錄"
}

# 自動模式
auto_mode() {
    print_header "🚀 自動版本更新模式"
    
    # 檢查 Flutter 環境
    check_flutter
    
    # 自動增加版本號
    local new_version=$(auto_increment_version)
    
    # 確認建構
    print_warning "將會執行以下操作："
    echo "  - 清理建構快取"
    echo "  - 重新取得依賴"
    echo "  - 建構發布版本 APK"
    echo "  - 輸出到 $APK_OUTPUT_DIR/ 目錄"
    echo ""
    read -p "確定要繼續嗎？ (y/N): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "操作已取消"
        # 還原版本變更
        git checkout -- pubspec.yaml 2>/dev/null || print_warning "無法還原版本號，請手動檢查"
        exit 0
    fi
    
    # 清理並建構
    clean_build
    
    if build_apk "$new_version"; then
        echo ""
        print_success "🎉 APK 發布完成！"
        print_info "版本: $new_version"
        print_info "檔案位置: ./$APK_OUTPUT_DIR/videotv.apk"
    else
        print_error "建構失敗，正在還原版本號..."
        git checkout -- pubspec.yaml 2>/dev/null || print_warning "無法還原版本號，請手動檢查"
        exit 1
    fi
}

# 手動模式
manual_mode() {
    print_header "🎯 手動版本更新模式"
    
    # 檢查 Flutter 環境
    check_flutter
    
    # 手動選擇版本號
    local new_version=$(manual_set_version)
    
    # 確認建構
    echo ""
    print_warning "將會執行以下操作："
    echo "  - 清理建構快取"
    echo "  - 重新取得依賴"
    echo "  - 建構發布版本 APK"
    echo "  - 輸出到 $APK_OUTPUT_DIR/ 目錄"
    echo ""
    read -p "確定要繼續嗎？ (y/N): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "操作已取消"
        # 還原版本變更
        git checkout -- pubspec.yaml 2>/dev/null || print_warning "無法還原版本號，請手動檢查"
        exit 0
    fi
    
    # 清理並建構
    clean_build
    
    if build_apk "$new_version"; then
        echo ""
        print_success "🎉 APK 發布完成！"
        print_info "版本: $new_version"
        print_info "檔案位置: ./$APK_OUTPUT_DIR/videotv.apk"
    else
        print_error "建構失敗，正在還原版本號..."
        git checkout -- pubspec.yaml 2>/dev/null || print_warning "無法還原版本號，請手動檢查"
        exit 1
    fi
}

# 主要流程
main() {
    # 處理命令行參數
    case "${1:-}" in
        --help|-h)
            show_usage
            exit 0
            ;;
        --auto|-a)
            auto_mode
            exit 0
            ;;
        "")
            manual_mode
            exit 0
            ;;
        *)
            print_error "未知參數: $1"
            show_usage
            exit 1
            ;;
    esac
}

# 檢查是否在正確的目錄
if [ ! -f "pubspec.yaml" ]; then
    print_error "請在 Flutter 專案根目錄執行此腳本"
    exit 1
fi

# 執行主要流程
main "$@" 
// 广告数据统计面板 - 主要JavaScript逻辑

class AdDataDashboard {
    constructor() {
        // 广告ID到广告名的映射（从后端API加载）
        this.adNameMap = {};
        this.init();
    }
    
    init() {
        this.bindEvents();
        this.updateCurrentTime();
        this.loadFilterOptions();
        
        // 定时更新时间
        setInterval(() => this.updateCurrentTime(), 1000);
    }
    
    bindEvents() {
        // 查询按钮
        const queryBtn = document.getElementById('query-btn');
        if (queryBtn) {
            queryBtn.addEventListener('click', () => this.queryData({ groupBy: 'ad_id', order: 'DESC' }));
        }
        
        // 重置按钮
        const resetBtn = document.getElementById('reset-btn');
        if (resetBtn) {
            resetBtn.addEventListener('click', () => this.resetFilters());
        }
        
        // 刷新按钮
        const refreshBtn = document.getElementById('refresh-btn');
        if (refreshBtn) {
            refreshBtn.addEventListener('click', () => {
                this.loadFilterOptions();
                this.queryData({ groupBy: 'ad_id', order: 'DESC' });
            });
        }
        
        // 关闭模态框
        const closeBtn = document.querySelector('.close');
        if (closeBtn) {
            closeBtn.addEventListener('click', () => this.hideModal());
        }
        
        // 点击模态框外部关闭
        window.addEventListener('click', (e) => {
            const modal = document.getElementById('error-modal');
            if (e.target === modal) {
                this.hideModal();
            }
        });
        
        // Enter键触发查询
        document.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') {
                this.queryData({ groupBy: 'ad_id', order: 'DESC' });
            }
        });
    }
    
    updateCurrentTime() {
        const currentTimeEl = document.getElementById('current-time');
        if (currentTimeEl) {
            const now = new Date();
            currentTimeEl.textContent = 
                now.toLocaleString('zh-CN', {
                    year: 'numeric',
                    month: '2-digit',
                    day: '2-digit',
                    hour: '2-digit',
                    minute: '2-digit',
                    second: '2-digit'
                });
        }
    }
    
    setDefaultDateRange(days = 14) {
        const ms = 24 * 60 * 60 * 1000;
        const today = new Date();
        // 以后端最大日期作为默认结束日（如果提供）
        const maxStr = this.dateRange?.max_date;
        const minStr = this.dateRange?.min_date;
        const end = maxStr ? new Date(maxStr) : today;
        let start = new Date(end.getTime() - (days - 1) * ms);
        if (minStr) {
            const min = new Date(minStr);
            if (start < min) start = min; // 夹取，避免超出可选范围导致空值
        }
        
        document.getElementById('end_date').value = end.toISOString().split('T')[0];
        document.getElementById('start_date').value = start.toISOString().split('T')[0];
        
        console.log('📅 Default date range set:', start.toISOString().split('T')[0], 'to', end.toISOString().split('T')[0]);
    }
    
    getAdName(adId) {
        return this.adNameMap[adId] || adId;
    }
    
    async loadFilterOptions() {
        try {
            const response = await fetch('/api/filter-options');
            const options = await response.json();
            
            if (options.error) {
                this.showError(options.error);
                return;
            }
            
            // 更新日期范围
            if (options.date_range) {
                this.dateRange = options.date_range;
                if (options.date_range.min_date) {
                    document.getElementById('start_date').min = options.date_range.min_date;
                }
                if (options.date_range.max_date) {
                    document.getElementById('end_date').max = options.date_range.max_date;
                }
            }
            
            // 加载广告映射关系
            this.adNameMap = options.ad_mapping || {};
            
            // 更新各个选择框
            this.updateSelectOptions('ds_id', options.ds_ids || []);
            this.updateSelectOptions('ad_id', options.ad_ids || [], true); // 广告ID使用友好名称
            this.updateSelectOptions('channel_id', options.channel_ids || []);
            this.updateSelectOptions('up_id', options.up_ids || []);
            // is_callback_sent选择器在HTML中已固定，不需要动态加载
            
            // 设置默认14天并发起默认查询
            this.setDefaultDateRange(14);
            console.log('🚀 Starting default query with ad_id grouping...');
            this.queryData({ groupBy: 'ad_id', order: 'DESC' });
            
        } catch (error) {
            console.error('加载筛选选项失败:', error);
            this.showError('加载筛选选项失败: ' + error.message);
        }
    }
    
    updateSelectOptions(selectId, options, useMapping = false) {
        const select = document.getElementById(selectId);
        const currentValue = select.value;
        
        // 清空现有选项（保留"全部"选项）
        select.innerHTML = '<option value="all">全部</option>';
        
        // 添加新选项
        options.forEach(option => {
            const optionElement = document.createElement('option');
            optionElement.value = option;
            
            if (useMapping && selectId === 'ad_id') {
                // 广告ID显示为 "ID - 友好名称" 格式
                const friendlyName = this.adNameMap[option];
                optionElement.textContent = friendlyName ? `${option} - ${friendlyName}` : option;
            } else {
                optionElement.textContent = option;
            }
            
            select.appendChild(optionElement);
        });
        
        // 恢复之前的选择（如果还存在）
        if (options.includes(currentValue)) {
            select.value = currentValue;
        }
    }
    
    getQueryParams() {
        const params = new URLSearchParams();
        
        // 获取所有筛选条件
        const filters = [
            'start_date', 'end_date', 'ds_id', 'ad_id',
            'channel_id', 'up_id', 'is_callback_sent'
        ];
        
        filters.forEach(filterId => {
            const element = document.getElementById(filterId);
            const value = element.value;
            if (value && value !== 'all' && value.trim() !== '') {
                params.append(filterId, value);
            }
        });
        
        return params;
    }
    
    async queryData(options = {}) {
        this.showLoading(true);
        
        try {
            const params = this.getQueryParams();
            if (options.groupBy) params.append('group_by', options.groupBy);
            if (options.order) params.append('order', options.order);
            
            console.log('📊 Query params:', params.toString());
            
            // 请求数据
            const dataResponse = await fetch(`/api/data?${params}`);
            const data = await dataResponse.json();

            if (!dataResponse.ok) {
                throw new Error(data.error || `数据接口错误(${dataResponse.status})`);
            }
            
            if (data.error) {
                this.showError(data.error);
                return;
            }
            
            // 更新界面
            this.updateDataTable(data.data);
            
        } catch (error) {
            console.error('查询数据失败:', error);
            this.showError('查询数据失败: ' + error.message);
        } finally {
            this.showLoading(false);
        }
    }
    
    updateDataTable(data) {
        const tbody = document.querySelector('#data-table tbody');
        tbody.innerHTML = '';
        
        if (!data || data.length === 0) {
            tbody.innerHTML = '<tr><td colspan="12" class="no-data">暂无数据</td></tr>';
            document.getElementById('data-count').textContent = '共 0 条数据';
            return;
        }
        
        let currentDate = null;
        let dateGroupIndex = 0;
        
        // 计算合计数据
        let totalRequests = 0;
        let totalActivated = 0;
        let totalRegistered = 0;
        let totalPaid = 0;
        let totalCallbacks = 0;
        let totalRequestSuccess = 0;
        let totalRequestFailed = 0;
        let totalCallbackFailed = 0;
        
        data.forEach(row => {
            // 检测日期变化，交替背景色
            if (row.date_day !== currentDate) {
                currentDate = row.date_day;
                dateGroupIndex++;
            }
            
            // 累计合计数据
            totalRequests += parseInt(row.request_count || 0);
            totalRequestSuccess += parseInt(row.request_success_count || 0);
            totalRequestFailed += parseInt(row.request_failed_count || 0);
            totalActivated += parseInt(row.activated_count || 0);
            totalRegistered += parseInt(row.registered_count || 0);
            totalPaid += parseInt(row.paid_count || 0);
            totalCallbacks += parseInt(row.total_callback_count || 0);
            totalCallbackFailed += parseInt(row.callback_failed_count || 0);
            
            const tr = document.createElement('tr');
            // 奇数日期组使用浅灰背景，偶数日期组无背景
            const bgClass = (dateGroupIndex % 2 === 1) ? 'date-group-odd' : 'date-group-even';
            tr.className = bgClass;
            
            tr.innerHTML = `
                <td>${row.date_day || '-'}</td>
                <td>${row.up_id || '-'}</td>
                <td>${row.ds_id || '-'}</td>
                <td>${row.ad_id || '-'}</td>
                <td>${this.getAdName(row.ad_id)}</td>
                <td>${row.channel_id || '-'}</td>
                <td class="number">${this.formatNumber(row.request_count)}</td>
                <td class="number">${this.formatNumber(row.request_success_count || 0)}</td>
                <td class="number">${this.formatNumber(row.request_failed_count || 0)}</td>
                <td class="number">${this.formatNumber(row.activated_count || 0)}</td>
                <td class="number">${this.formatNumber(row.registered_count || 0)}</td>
                <td class="number">${this.formatNumber(row.paid_count || 0)}</td>
                <td class="number">${this.formatNumber(row.total_callback_count || 0)}</td>
                <td class="number">${this.formatNumber(row.callback_failed_count || 0)}</td>
                <td class="number">${row.callback_rate}%</td>
                <td>${row.updated_at || '-'}</td>
            `;
            tbody.appendChild(tr);
        });
        
        // 添加合计行
        if (data.length > 0) {
            const totalRate = totalRequests > 0 ? (totalCallbacks * 100 / totalRequests).toFixed(2) : '0.00';
            const totalTr = document.createElement('tr');
            totalTr.className = 'summary-row';
            
            totalTr.innerHTML = `
                <td><strong>合计</strong></td>
                <td>-</td>
                <td>-</td>
                <td>-</td>
                <td>-</td>
                <td>-</td>
                <td class="number"><strong>${this.formatNumber(totalRequests)}</strong></td>
                <td class="number"><strong>${this.formatNumber(totalRequestSuccess)}</strong></td>
                <td class="number"><strong>${this.formatNumber(totalRequestFailed)}</strong></td>
                <td class="number"><strong>${this.formatNumber(totalActivated)}</strong></td>
                <td class="number"><strong>${this.formatNumber(totalRegistered)}</strong></td>
                <td class="number"><strong>${this.formatNumber(totalPaid)}</strong></td>
                <td class="number"><strong>${this.formatNumber(totalCallbacks)}</strong></td>
                <td class="number"><strong>${this.formatNumber(totalCallbackFailed)}</strong></td>
                <td class="number"><strong>${totalRate}%</strong></td>
                <td>-</td>
            `;
            tbody.appendChild(totalTr);
        }
        
        document.getElementById('data-count').textContent = `共 ${data.length} 条数据`;
    }
    

    
    resetFilters() {
        // 重置所有筛选器
        document.getElementById('start_date').value = '';
        document.getElementById('end_date').value = '';
        
        const selects = ['ds_id', 'ad_id', 'channel_id', 'up_id', 'is_callback_sent'];
        selects.forEach(id => {
            document.getElementById(id).value = 'all';
        });
        
        // 重新设置默认日期范围
        this.setDefaultDateRange(14);
        
        // 自动查询（保持与默认一致的排序）
        this.queryData({ groupBy: 'ad_id', order: 'DESC' });
    }
    
    showLoading(show) {
        const loading = document.getElementById('loading');
        loading.style.display = show ? 'flex' : 'none';
    }
    
    showError(message) {
        document.getElementById('error-message').textContent = message;
        document.getElementById('error-modal').style.display = 'block';
    }
    
    hideModal() {
        document.getElementById('error-modal').style.display = 'none';
    }
    
    formatNumber(num) {
        if (num == null || num === '') return '-';
        return parseInt(num).toLocaleString('zh-CN');
    }
}

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', () => {
    new AdDataDashboard();
});


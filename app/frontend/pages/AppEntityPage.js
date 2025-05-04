import React, { useState, useEffect } from "react";
import { Button, Input, Modal, message, Popconfirm, Form, Tooltip, Select, Table, Typography, Space,Switch } from "antd";
import { ProTable } from "@ant-design/pro-components";
import { apiFetch } from "@/lib/api/fetch";
import { CopyOutlined, PlusOutlined, DeleteOutlined ,EditOutlined} from "@ant-design/icons";

const { Text } = Typography;

const AppEntityPage = () => {
    // 添加新的状态变量
    const [apiKeyForm] = Form.useForm();
    const [editApiKeyModalVisible, setEditApiKeyModalVisible] = useState(false);
    const [editingApiKey, setEditingApiKey] = useState(null);

  const statusOptions = [
    { label: "启用", value: "active" },
    { label: "禁用", value: "inactive" },
  ];

  const [form] = Form.useForm();
  const [modalVisible, setModalVisible] = useState(false);
  const [apiKeyModalVisible, setApiKeyModalVisible] = useState(false);
  const [tableData, setTableData] = useState([]);
  const [pagination, setPagination] = useState({
    current: 1,
    pageSize: 10,
    total: 0,
  });
  const [loading, setLoading] = useState(false);
  const [editingEntity, setEditingEntity] = useState(null);
  const [currentAppId, setCurrentAppId] = useState(null);
  const [apiKeys, setApiKeys] = useState({});
  const [newApiKey, setNewApiKey] = useState(null);

  // 获取 AppEntity 列表
  const fetchEntities = async (params = {}) => {
    setLoading(true);
    try {
      const response = await apiFetch(`/api/app_entities?query=${JSON.stringify(params)}`);
      setTableData(response.data);
      setPagination({
        current: response.pagination.current,
        pageSize: response.pagination.pageSize,
        total: response.pagination.total,
      });
    } catch (err) {
      message.error("获取应用列表失败");
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  // 获取应用的API密钥
  const fetchApiKeys = async (appId) => {
    try {
      const response = await apiFetch(`/api/app_entities/${appId}/manage_api_keys`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action_type: "list" }),
      });
      setApiKeys(prev => ({ ...prev, [appId]: response }));
      return response;
    } catch (err) {
      message.error("获取API密钥失败");
      console.error(err);
      return [];
    }
  };

  // 创建新的API密钥
  const createApiKey = async (appId) => {
    try {
      const response = await apiFetch(`/api/app_entities/${appId}/manage_api_keys`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action_type: "create" }),
      });
      
      // 更新API密钥列表
      await fetchApiKeys(appId);
      
      // 设置新的API密钥用于显示
      setNewApiKey(response);
      setApiKeyModalVisible(true);
      
      return response;
    } catch (err) {
      message.error("创建API密钥失败");
      console.error(err);
    }
  };
    // 添加编辑API密钥函数
    const handleEditApiKey = (record) => {
      setEditingApiKey(record);
      apiKeyForm.setFieldsValue({
        remark: record.remark || '',
      });
      setEditApiKeyModalVisible(true);
    };
  
    // 添加更新API密钥函数
    const updateApiKeyRemark = async () => {
      try {
        await apiKeyForm.validateFields();
        const values = apiKeyForm.getFieldsValue();
        
        await apiFetch(`/api/app_entities/${currentAppId}/manage_api_keys`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ 
            action_type: "update", 
            key_id: editingApiKey.id,
            remark: values.remark
          }),
        });
        
        message.success("API密钥备注更新成功");
        
        // 更新API密钥列表
        await fetchApiKeys(currentAppId);
        
        // 关闭模态框
        setEditApiKeyModalVisible(false);
        setEditingApiKey(null);
        apiKeyForm.resetFields();
      } catch (err) {
        message.error("更新API密钥备注失败");
        console.error(err);
      }
    };
 // 添加状态切换函数
  const toggleApiKeyStatus = async (appId, keyId, newStatus) => {
    try {
      await apiFetch(`/api/app_entities/${appId}/manage_api_keys`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ 
          action_type: "toggle_status", 
          key_id: keyId,
          active: newStatus
        }),
      });
      
      message.success(`API密钥${newStatus ? '启用' : '停用'}成功`);
      
      // 更新API密钥列表
      await fetchApiKeys(appId);
    } catch (err) {
      message.error(`${newStatus ? '启用' : '停用'}API密钥失败`);
      console.error(err);
    }
  };
  // 删除API密钥
  const deleteApiKey = async (appId, keyId) => {
    try {
      await apiFetch(`/api/app_entities/${appId}/manage_api_keys`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action_type: "delete", key_id: keyId }),
      });
      
      message.success("API密钥删除成功");
      
      // 更新API密钥列表
      await fetchApiKeys(appId);
    } catch (err) {
      message.error("删除API密钥失败");
      console.error(err);
    }
  };
  

  // 创建或更新 AppEntity
  const handleSubmit = async () => {
    try {
      await form.validateFields();
      const values = form.getFieldsValue();

      if (editingEntity) {
        // 更新应用
        await apiFetch(`/api/app_entities/${editingEntity}`, {
          method: "PUT",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(values),
        });
        message.success("应用更新成功");
      } else {
        // 创建应用
        const response = await apiFetch("/api/app_entities", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(values),
        });
        message.success("应用创建成功");
        
        // 显示新创建的API密钥
        if (response.api_key) {
          setNewApiKey(response.api_key);
          setApiKeyModalVisible(true);
        }
      }

      setModalVisible(false);
      form.resetFields();
      setEditingEntity(null);
      fetchEntities();
    } catch (err) {
      message.error(err.message || "操作失败");
    }
  };

  const handleDelete = async (id) => {
    try {
      await apiFetch(`/api/app_entities/${id}`, {
        method: "DELETE",
      });
  
      message.success("删除应用成功");
      fetchEntities({
        current: pagination.current,
        pageSize: pagination.pageSize,
      });
    } catch (err) {
      message.error(err.message || "删除失败");
    }
  };

  // 编辑应用
  const handleEdit = (record) => {
    setEditingEntity(record.id);
    form.setFieldsValue(record);
    setModalVisible(true);
  };

  // 初始化加载
  useEffect(() => {
    fetchEntities();
  }, []);

  // API密钥表格列定义
  const apiKeyColumns = [
    {
      title: 'API Key',
      dataIndex: 'apikey',
      key: 'apikey',
      render: (text) => (
        <Tooltip title="点击复制">
          <Text 
            copyable={{ text, onCopy: () => message.success("API Key已复制") }}
            style={{ cursor: 'pointer' }}
          >
            {text}
          </Text>
        </Tooltip>
      ),
    },
    {
      title: '备注',
      dataIndex: 'remark',
      key: 'remark',
      render: (text) => text || '-',
    },
    {
      title: '状态',
      dataIndex: 'active',
      key: 'active',
      render: (active, record) => (
        <Switch
          checkedChildren="启用"
          unCheckedChildren="停用"
          checked={active}
          onChange={(checked) => toggleApiKeyStatus(currentAppId, record.id, checked)}
        />
      ),
    },
    {
      title: '创建时间',
      dataIndex: 'created_at',
      key: 'created_at',
    },
    {
      title: '操作',
      key: 'action',
      render: (_, record) => (
        <Space>
          <Button 
            type="text" 
            icon={<EditOutlined />}
            onClick={() => handleEditApiKey(record)}
          >
            编辑
          </Button>
          <Popconfirm
            title="确定要删除此API密钥吗?"
            onConfirm={() => deleteApiKey(currentAppId, record.id)}
            okText="确定"
            cancelText="取消"
          >
            <Button type="text" danger icon={<DeleteOutlined />}>
              删除
            </Button>
          </Popconfirm>
        </Space>
      ),
    },
  ];

  // 主表格列定义
  const columns = [
    {
      title: "名称",
      dataIndex: "name",
      key: "name",
      sorter: true,
    },
    {
      title: "描述",
      dataIndex: "description",
      key: "description",
    },
    {
      title: "状态",
      dataIndex: "status",
      key: "status",
      render: (status) => {
        const statusMap = { 'active': "启用", 'inactive': "禁用"};
        return statusMap[status] || "未知";
      },
    },
    {
      title: "操作",
      valueType: "option",
      render: (text, record) => [
        <a key="edit" onClick={() => handleEdit(record)}>
          编辑
        </a>,
        <Popconfirm
          key="delete"
          title="确定要删除此应用吗?"
          onConfirm={() => handleDelete(record.id)}
          okText="确定"
          cancelText="取消"
        >
          <a style={{ color: "red" }}>删除</a>
        </Popconfirm>,
        <a
          key="manageTables"
          href={`dynamic_tables/${record.id}`}
          style={{ color: "blue" }}
        >
          管理表格
        </a>,
      ],
    },
  ];

  return (
    <div>
      <ProTable
        headerTitle="应用管理"
        rowKey="id"
        columns={columns}
        dataSource={tableData}
        loading={loading}
        pagination={pagination}
        search={false}
        request={async (params = {}) => {
          await fetchEntities(params);
          return {
            data: tableData,
            success: true,
          };
        }}
        expandable={{
          expandedRowRender: (record) => {
            if (!apiKeys[record.id]) {
              // 首次展开时加载API密钥
              fetchApiKeys(record.id);
            }
            
            setCurrentAppId(record.id);
            
            return (
              <div style={{ margin: 0 }}>
                <div style={{ marginBottom: 16 }}>
                  <Button 
                    type="primary" 
                    icon={<PlusOutlined />} 
                    onClick={() => createApiKey(record.id)}
                  >
                    创建新API密钥
                  </Button>
                </div>
                <Table 
                  columns={apiKeyColumns} 
                  dataSource={apiKeys[record.id] || []} 
                  rowKey="id"
                  pagination={false}
                  size="small"
                  locale={{ emptyText: "暂无API密钥数据" }}
                />
              </div>
            );
          },
          onExpand: (expanded, record) => {
            if (expanded) {
              setCurrentAppId(record.id);
              fetchApiKeys(record.id);
            }
          },
        }}
        toolBarRender={() => [
          <Button
            key="add"
            type="primary"
            onClick={() => {
              form.resetFields();
              setEditingEntity(null);
              setModalVisible(true);
            }}
          >
            创建新应用
          </Button>,
        ]}
      />
      
      {/* 应用表单 */}
      <Modal
        title={editingEntity ? "编辑应用" : "创建新应用"}
        open={modalVisible}
        onCancel={() => {
          setModalVisible(false);
          setEditingEntity(null);
          form.resetFields();
        }}
        footer={[
          <Button
            key="cancel"
            onClick={() => {
              setModalVisible(false);
              setEditingEntity(null);
              form.resetFields();
            }}
          >
            取消
          </Button>,
          <Button key="submit" type="primary" onClick={handleSubmit}>
            {editingEntity ? "更新" : "创建"}
          </Button>,
        ]}
      >
        <Form form={form} layout="vertical">
          <Form.Item
            name="name"
            label="名称"
            rules={[{ required: true, message: "请输入名称" }]}
          >
            <Input placeholder="请输入应用名称" />
          </Form.Item>
          <Form.Item name="description" label="描述">
            <Input.TextArea placeholder="请输入描述" />
          </Form.Item>
          <Form.Item
            name="status"
            label="状态"
            rules={[{ message: "请选择状态" }]}
            hidden={!editingEntity}
          >
            <Select
              placeholder="请选择状态"
              options={statusOptions}
            />
          </Form.Item>
        </Form>
      </Modal>
      
      {/* API密钥显示弹窗 */}
      <Modal
        title="API密钥已创建"
        open={apiKeyModalVisible}
        onCancel={() => setApiKeyModalVisible(false)}
        footer={[
          <Button key="close" onClick={() => setApiKeyModalVisible(false)}>
            关闭
          </Button>,
        ]}
      >
        <p>请妥善保存以下API密钥信息，API Secret将只显示一次：</p>
        <Space direction="vertical" style={{ width: '100%' }}>
          <Input
            addonBefore="API Key"
            value={newApiKey?.apikey}
            readOnly
            addonAfter={
              <Tooltip title="复制">
                <CopyOutlined
                  onClick={() => {
                    navigator.clipboard.writeText(newApiKey?.apikey);
                    message.success("API Key已复制到剪贴板");
                  }}
                />
              </Tooltip>
            }
          />
          <Input
            addonBefore="API Secret"
            value={newApiKey?.apisecret}
            readOnly
            addonAfter={
              <Tooltip title="复制">
                <CopyOutlined
                  onClick={() => {
                    navigator.clipboard.writeText(newApiKey?.apisecret);
                    message.success("API Secret已复制到剪贴板");
                  }}
                />
              </Tooltip>
            }
          />
        </Space>
      </Modal>
      {/* 添加API密钥编辑模态框 */}
      <Modal
        title="编辑API密钥"
        open={editApiKeyModalVisible}
        onCancel={() => {
          setEditApiKeyModalVisible(false);
          setEditingApiKey(null);
          apiKeyForm.resetFields();
        }}
        footer={[
          <Button
            key="cancel"
            onClick={() => {
              setEditApiKeyModalVisible(false);
              setEditingApiKey(null);
              apiKeyForm.resetFields();
            }}
          >
            取消
          </Button>,
          <Button key="submit" type="primary" onClick={updateApiKeyRemark}>
            更新
          </Button>,
        ]}
      >
        <Form form={apiKeyForm} layout="vertical">
          <Form.Item
            name="remark"
            label="备注"
            rules={[{ max: 255, message: "备注不能超过255个字符" }]}
          >
            <Input.TextArea 
              placeholder="请输入备注信息，如用途或所属应用" 
              rows={4}
              showCount
              maxLength={255}
            />
          </Form.Item>
        </Form>
        <div style={{ marginTop: '10px', color: '#888' }}>
          <p>可以在备注中记录API密钥的用途或使用此密钥的应用信息</p>
        </div>
      </Modal>
    </div>
  );
};

export default AppEntityPage;
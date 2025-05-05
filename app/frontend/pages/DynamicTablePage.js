import React, { useState, useEffect } from "react";
import { Button, Input, Modal, message, Popconfirm, Form, Tooltip } from "antd";
import { InfoCircleOutlined } from "@ant-design/icons";
import { ProTable } from "@ant-design/pro-components";
import FieldEditor from "@/components/FieldEditor";
import { apiFetch } from "@/lib/api/fetch";
import { ArrowLeftOutlined } from "@ant-design/icons";
import { useParams ,useNavigate } from "react-router";
const DynamicTablePage = () => {
  const navigate = useNavigate(); // 确保已经导入
  const { appId } = useParams();
  const [form] = Form.useForm();
  const [fields, setFields] = useState([]); // 字段数据
  const [modalVisible, setModalVisible] = useState(false);
  const [editableKeys, setEditableRowKeys] = useState([]); // 可编辑行的 key
  const [tableData, setTableData] = useState([]); // 表格列表数据
  const [pagination, setPagination] = useState({
    current: 1,
    pageSize: 10,
    total: 0,
  });
  const [loading, setLoading] = useState(false);
  const [editingTable, setEditingTable] = useState(null); // 当前编辑的表格ID
  const [fetchingFields, setFetchingFields] = useState(false); // 加载字段状态

  // 获取表格列表
  const fetchTables = async (params = {}) => {
    setLoading(true);
    try {
      const queryParams = {
        ...params, // 从 useParams 获取的 appId
      };
      const response = await apiFetch(
        `/api/dynamic_tables?query=${JSON.stringify(
          queryParams
        )}&appId=${appId}`
      );

      // 更新状态
      setTableData(response.data || []);
      setPagination({
        current: response.pagination.current,
        pageSize: response.pagination.pageSize,
        total: response.pagination.total,
      });
    } catch (err) {
      message.error("获取表格列表失败");
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  // 获取表格详情（包括字段）
  const fetchTableDetail = async (tableId) => {
    setFetchingFields(true);
    try {
      const response = await apiFetch(`/api/dynamic_tables/${tableId}`);
      return response || { dynamic_fields: [] }; // 确保返回有效对象
    } catch (err) {
      message.error("获取表格详情失败");
      console.error(err);
      return { dynamic_fields: [] }; // 错误时返回空字段数组
    } finally {
      setFetchingFields(false);
    }
  };

  const handleCreateTable = async () => {
    try {
      await form.validateFields();
      const values = form.getFieldsValue();

      const processedFields = fields.map((field) => ({
        ...field,
        id: null, // 确保新字段的ID为null
        name: field.name,
        field_type: field.field_type,
        required: !!field.required, // 确保布尔值
      }));

      await apiFetch("/api/dynamic_tables", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          table_name: values.table_name,
          api_identifier: values.api_identifier,
          webhook_url: values.webhook_url,
          fields: processedFields,
          app_entity: appId,
        }),
      });

      message.success("表格创建成功");
      setModalVisible(false);
      setFields([]); // 清空字段数据
      form.resetFields(); // 重置表单
      fetchTables(); // 刷新表格列表
    } catch (err) {
      message.error(err.message || "创建失败");
    }
  };

  // 处理更新表格
  const handleUpdateTable = async () => {
    if (!editingTable) return;

    try {
      // 使用Form进行验证
      await form.validateFields();
      const values = form.getFieldsValue();

      // 处理字段数据，确保每个字段的格式正确
      const processedFields = fields.map((field) => ({
        ...field,
        // 已有字段保留ID，新字段ID为null
        id: field.isNew ? null : field.id,
        name: field.name,
        field_type: field.field_type,
        required: !!field.required, // 确保布尔值
      }));

      await apiFetch(`/api/dynamic_tables/${editingTable}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          table_name: values.table_name,
          api_identifier: values.api_identifier,
          webhook_url: values.webhook_url,
          fields: processedFields,
        }),
      });

      message.success("表格更新成功");
      setModalVisible(false);
      setFields([]); // 清空字段数据
      form.resetFields(); // 重置表单
      setEditingTable(null); // 清除编辑状态
      fetchTables(); // 刷新表格列表
    } catch (err) {
      if (err.errorFields) {
        // 表单验证错误
        return;
      }
      message.error("更新失败: " + (err.message || "未知错误"));
      console.error("更新表格失败:", err);
    }
  };

  const handleDeleteTable = async (id) => {
    try {
      const response = await apiFetch(`/api/dynamic_tables/${id}`, {
        method: "DELETE",
      });

      message.success("表格删除成功");
      // 重新加载表格数据
      fetchTables({
        current: pagination.current,
        pageSize: pagination.pageSize,
      });
    } catch (err) {
      message.error("删除失败: " + (err.message || "未知错误"));
      console.error("删除表格失败:", err);
    }
  };

  // 处理编辑按钮点击
  const handleEdit = async (record) => {
    // 设置编辑状态
    setEditingTable(record.id);

    // 先填充基本数据
    form.setFieldsValue({
      table_name: record.table_name,
      api_identifier: record.api_identifier,
      webhook_url: record.webhook_url,
    });

    // 不论record中是否有字段数据，都从服务器获取最新数据
    // 这确保我们总是使用最新的字段定义
    setFetchingFields(true);
    try {
      const detailData = await fetchTableDetail(record.id);
      if (
        detailData &&
        detailData.dynamic_fields &&
        detailData.dynamic_fields.length > 0
      ) {
        // 为每个字段添加key属性（用于EditableProTable）
        setFields(
          detailData.dynamic_fields.map((f) => ({
            ...f,
            key: f.id,
          }))
        );
      } else {
        setFields([]);
        console.log("该表格没有字段或字段加载失败");
      }
    } catch (err) {
      console.error("加载字段数据失败:", err);
      setFields([]);
    } finally {
      setFetchingFields(false);
      setModalVisible(true); // 无论结果如何都显示模态框
    }
  };

  // 渲染API地址带复制功能
  const renderApiUrl = (text, record) => {
    const apiUrl =
      record.api_url || `/api/v1/${record.table_name.toLowerCase()}`;
    const baseUrl = window.location.origin;
    const fullUrl = `${baseUrl}${apiUrl}`;

    return (
      <Tooltip title="点击复制API地址">
        <span
          style={{ cursor: "pointer", color: "#1890ff" }}
          onClick={() => {
            navigator.clipboard
              .writeText(fullUrl)
              .then(() => message.success("API地址已复制"))
              .catch((err) => message.error("复制失败"));
          }}
        >
          {apiUrl}
        </span>
      </Tooltip>
    );
  };

  const tableColumns = [
    {
      title: "表格名称",
      dataIndex: "table_name",
      key: "table_name",
      sorter: true,
    },
    {
      title: "API地址",
      dataIndex: "api_url",
      key: "api_url",
      render: renderApiUrl,
    },
    {
      title: "webhook地址",
      dataIndex: "webhook_url",
      key: "webhook_url",
    },
    {
      title: "创建时间",
      dataIndex: "created_at",
      key: "created_at",
      sorter: true,
    },
    {
      title: "操作",
      valueType: "option",
      render: (text, record) => [
        <a key="fields" href={`/admin/dynamic_fields/${record.id}`}>
          字段管理
        </a>,
        <a key="data" href={`/admin/dynamic_records/${record.id}`}>
          数据管理
        </a>,
        <a key="edit" onClick={() => handleEdit(record)}>
          编辑
        </a>,
        <Popconfirm
          key="delete"
          title="确定要删除此表格吗?"
          description="删除后将无法恢复，表中所有数据将丢失!"
          onConfirm={() => handleDeleteTable(record.id)}
          okText="确定"
          cancelText="取消"
        >
          <a style={{ color: "red" }}>删除</a>
        </Popconfirm>,
      ],
    },
  ];

  // 初始加载
  useEffect(() => {
    fetchTables();
    localStorage.setItem("appId", appId); // 将appId存储到localStorage
  }, []);

  // 添加返回函数
  const handleGoBack = () => {

    navigate(`/admin/apps`);
  };

  // 模态框标题和提交按钮根据当前模式确定
  const modalTitle = editingTable ? "编辑表格" : "创建新表格";
  const modalSubmitText = editingTable ? "更新" : "创建";
  const handleSubmit = editingTable ? handleUpdateTable : handleCreateTable;

  return (
    <div>
      <div style={{ marginBottom: 16 }}>
        <Button icon={<ArrowLeftOutlined />} onClick={handleGoBack}>
          返回应用列表
        </Button>
      </div>
      <ProTable
        headerTitle="动态表格管理"
        rowKey="id"
        columns={tableColumns}
        dataSource={tableData}
        loading={loading}
        pagination={pagination}
        search={true}
        request={async (params = {}) => {
          await fetchTables(params);
          return {
            data: tableData,
            success: true,
          };
        }}
        toolBarRender={() => [
          <Button
            key="add"
            type="primary"
            onClick={() => {
              form.resetFields();
              setFields([]);
              setEditingTable(null); // 确保是创建模式
              setModalVisible(true);
            }}
          >
            创建新表格
          </Button>,
        ]}
      />
      <Modal
        width={600}
        title={modalTitle}
        open={modalVisible}
        onCancel={() => {
          setModalVisible(false);
          setEditingTable(null);
          setFields([]);
          form.resetFields();
        }}
        footer={[
          <Button
            key="cancel"
            onClick={() => {
              setModalVisible(false);
              setEditingTable(null);
              setFields([]);
              form.resetFields();
            }}
          >
            取消
          </Button>,
          <Button
            key="submit"
            type="primary"
            onClick={handleSubmit}
            loading={fetchingFields}
          >
            {modalSubmitText}
          </Button>,
        ]}
      >
        <Form form={form} layout="vertical">
          <Form.Item
            name="table_name"
            label="表格名称"
            rules={[
              { required: true, message: "请输入表格名称" },
              {
                pattern: /^[a-zA-Z_][a-zA-Z0-9_]*$/,
                message: "只能包含字母、数字、下划线，且不能以数字开头",
              },
            ]}
          >
            <Input placeholder="例如: products, user_profiles" />
          </Form.Item>

          <Form.Item
            name="api_identifier"
            label={
              <span>
                API标识符{" "}
                <Tooltip title="用于API访问路径，例如: /api/v1/products。可选，留空则使用表名。">
                  <InfoCircleOutlined style={{ marginLeft: 5 }} />
                </Tooltip>
              </span>
            }
            rules={[
              {
                pattern: /^[a-z][a-z0-9_]*$/,
                message: "只能包含小写字母、数字和下划线，且必须以字母开头",
              },
            ]}
          >
            <Input placeholder="例如: products, user_profiles" />
          </Form.Item>
          <Form.Item
            name="webhook_url"
            label={
              <span>
                Webhook URL{" "}
                <Tooltip title="当表格数据发生变化时，将触发此 URL 的回调。">
                  <InfoCircleOutlined style={{ marginLeft: 5 }} />
                </Tooltip>
              </span>
            }
            rules={[
              { type: "url", message: "请输入有效的 URL 地址" },
              { max: 255, message: "URL 长度不能超过 255 个字符" },
            ]}
          >
            <Input placeholder="例如: https://example.com/webhook" />
          </Form.Item>
        </Form>

        <div style={{ marginTop: 16 }}>
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              alignItems: "center",
              marginBottom: 8,
            }}
          >
            <label>字段定义：</label>
            {fetchingFields && (
              <span style={{ color: "#1890ff" }}>加载字段中...</span>
            )}
          </div>
          <FieldEditor
            fields={fields}
            setFields={setFields}
            editableKeys={editableKeys}
            setEditableRowKeys={setEditableRowKeys}
          />
        </div>
      </Modal>
    </div>
  );
};

export default DynamicTablePage;

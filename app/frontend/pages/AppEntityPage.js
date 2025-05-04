import React, { useState, useEffect } from "react";
import { Button, Input, Modal, message, Popconfirm, Form, Tooltip,Select } from "antd";
import { ProTable } from "@ant-design/pro-components";
import { apiFetch } from "@/lib/api/fetch";
import { CopyOutlined } from "@ant-design/icons";

const AppEntityPage = () => {
  const statusOptions = [
    { label: "启用", value: "active" },
    { label: "禁用", value: "inactive" },
  ];

  const [form] = Form.useForm();
  const [modalVisible, setModalVisible] = useState(false);
  const [tokenModalVisible, setTokenModalVisible] = useState(false);
  const [tableData, setTableData] = useState([]);
  const [pagination, setPagination] = useState({
    current: 1,
    pageSize: 10,
    total: 0,
  });
  const [loading, setLoading] = useState(false);
  const [editingEntity, setEditingEntity] = useState(null);
  const [newToken, setNewToken] = useState(""); // 用于存储新创建的秘钥
  const [temporaryTokens, setTemporaryTokens] = useState({});
  // 获取 AppEntity 列表
  const fetchEntities = async (params = {}) => {
    setLoading(true);
    try {
      const response = await apiFetch(`/api/app_entities?query=${JSON.stringify(params)}`);
      const dataWithTokens = response.data.map((entity) => ({
        ...entity,
        token: temporaryTokens[entity.id] || "********", // 如果有临时密钥则展示，否则显示隐藏的密钥
      }));
      setTableData(dataWithTokens);
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
        setNewToken(response.token); // 设置新创建的秘钥
        setTokenModalVisible(true); // 显示秘钥弹窗
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
      title: "密钥",
      dataIndex: "token",
      key: "token",
      render: (token, record) => (
        <Tooltip title={token !== "********" ? "点击复制" : "密钥不可见"}>
          <span
            style={{ cursor: token !== "********" ? "pointer" : "not-allowed" }}
            onClick={() => {
              if (token !== "********") {
                navigator.clipboard.writeText(token);
                message.success("密钥已复制到剪贴板");
              }
            }}
          >
            {token}
          </span>
        </Tooltip>
      ),
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
           <a
           key="resetToken"
           onClick={() => handleResetToken(record.id)}
           style={{ color: "orange" }}
         >
           重置密钥
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

  const handleResetToken = (id) => {
    Modal.confirm({
      title: "确认重置密钥",
      content: "重置密钥后，旧密钥将失效，是否继续？",
      okText: "确认",
      cancelText: "取消",
      onOk: async () => {
        try {
          const response = await apiFetch(`/api/app_entities/${id}/reset_token`, {
            method: "POST",
          });
          message.success("密钥已重置");

          // 更新临时密钥状态
          setTemporaryTokens((prevTokens) => ({
            ...prevTokens,
            [id]: response.token,
          }));

          // 更新表格数据
          setTableData((prevData) =>
            prevData.map((entity) =>
              entity.id === id ? { ...entity, token: response.token } : entity
            )
          );

          Modal.info({
            title: "新密钥已生成",
            content: (
              <Input
                value={response.token}
                readOnly
                addonAfter={
                  <Tooltip title="复制">
                    <CopyOutlined
                      onClick={() => {
                        navigator.clipboard.writeText(response.token);
                        message.success("新密钥已复制到剪贴板");
                      }}
                    />
                  </Tooltip>
                }
              />
            ),
          });
        } catch (err) {
          message.error(err.message || "重置密钥失败");
        }
      },
    });
  };
  return (
    <div>
      <ProTable
        headerTitle="AppEntity 管理"
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
              hidden={!editingEntity} // 使用 hidden 属性代替 style
            >
              <Select
                placeholder="请选择状态"
                options={statusOptions} // 使用状态选项
              />
            </Form.Item>
        </Form>
      </Modal>
      <Modal
        title="秘钥生成成功"
        open={tokenModalVisible}
        onCancel={() => setTokenModalVisible(false)}
        footer={[
          <Button key="close" onClick={() => setTokenModalVisible(false)}>
            关闭
          </Button>,
        ]}
      >
        <p>以下是新生成的秘钥，请妥善保存：</p>
        <Input
          value={newToken}
          readOnly
          addonAfter={
            <Tooltip title="复制">
              <CopyOutlined
                onClick={() => {
                  navigator.clipboard.writeText(newToken);
                  message.success("秘钥已复制到剪贴板");
                }}
              />
            </Tooltip>
          }
        />
      </Modal>
    </div>
  );
};

export default AppEntityPage;
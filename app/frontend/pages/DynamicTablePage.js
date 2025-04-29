import React, { useState, useEffect } from "react";
import { Button, Input, Modal, message ,Popconfirm} from "antd";
import {
  EditableProTable,
  ProCard,
  ProTable,
  ProFormField,
  ProFormRadio,
} from "@ant-design/pro-components";
import FieldEditor from "@/components/FieldEditor";
import { apiFetch } from "@/lib/api/fetch";

const DynamicTablePage = () => {
  const [fields, setFields] = useState([]); // 字段数据
  const [tableName, setTableName] = useState(""); // 表格名称
  const [modalVisible, setModalVisible] = useState(false);
  const [editableKeys, setEditableRowKeys] = useState([]); // 可编辑行的 key
  const [tableData, setTableData] = useState([]); // 表格列表数据
  const [pagination, setPagination] = useState({
    current: 1,
    pageSize: 10,
    total: 0,
  });
  const [loading, setLoading] = useState(false);



  // 获取表格列表
  const fetchTables = async (params = {}) => {
    console.log(params)
    setLoading(true);
    try {

      const response = await apiFetch(`/api/dynamic_tables?query=${JSON.stringify(params)}`);

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

  const handleCreateTable = async () => {
    try {
      const processedFields = fields.map((field) => ({
        ...field,
        id: null, // 确保新字段的 ID 为 null
      }));

      const response = await apiFetch("/api/dynamic_tables", {
        method: "POST",
        body: JSON.stringify({
          table_name: tableName,
          fields: processedFields, // 将字段数据一起提交
        }),
      });
      message.success("表格创建成功");
      setModalVisible(false);
      setFields([]); // 清空字段数据
      setTableName(""); // 清空表格名称
      fetchTables(); // 刷新表格列表
    } catch (err) {
      message.error("创建失败");
    }
  };

  const handleDeleteTable = async (id) => {
    try {
      const response = await apiFetch(`/api/dynamic_tables/${id}`, {
        method: "DELETE",
      });
      
      if (response.status) {
        message.success("表格删除成功");
        // 重新加载表格数据
        fetchTables({
          current: pagination.current,
          pageSize: pagination.pageSize,
        });
      } else {
        message.error("删除失败");
      }
    } catch (err) {
      message.error("删除失败: " + (err.message || "未知错误"));
      console.error(err);
    }
  };

  const tableColumns = [
    {
      title: "表格名称",
      dataIndex: "table_name",
      key: "table_name",
      sorter: true,
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
        <Popconfirm
          key="delete"
          title="确定要删除此表格吗?"
          description="删除后将无法恢复，表中所有数据将丢失!"
          onConfirm={() => handleDeleteTable(record.id)}
          okText="确定"
          cancelText="取消"
        >
          <a style={{ color: 'red' }}>删除</a>
        </Popconfirm>
      ],
    },
  ];

  return (
    <div>
      <ProTable
        headerTitle="动态表格管理"
        rowKey="id"
        columns={tableColumns}
        dataSource={tableData}
        loading={loading}
        pagination={pagination}
        search={true}
        // options={{
        //   density: true,
        //   fullScreen: true,
        //   reload: () =>
        //     fetchTables({
        //       current: pagination.current,
        //       pageSize: pagination.pageSize,
        //     }),
        // }}
        // onChange={handleTableChange}
        request={async (params = {}) => {
          await fetchTables(params);
          return {
            data:tableData,
            success: true,
          };
        }}
        toolBarRender={() => [
          <Button
            key="add"
            type="primary"
            onClick={() => setModalVisible(true)}
          >
            创建新表格
          </Button>,
        ]}
      />
      {/* <Button type="primary" onClick={() => setModalVisible(true)} style={{ marginTop: 16 }}>
        
      </Button> */}
      <Modal
        width={600}
        title="创建新表格"
        open={modalVisible}
        onCancel={() => setModalVisible(false)}
        footer={[
          <Button key="cancel" onClick={() => setModalVisible(false)}>
            取消
          </Button>,
          <Button key="submit" type="primary" onClick={handleCreateTable}>
            创建
          </Button>,
        ]}
      >
        <div style={{ marginBottom: 16 }}>
          <label>表格名称：</label>
          <Input
            value={tableName}
            onChange={(e) => setTableName(e.target.value)}
            placeholder="请输入表格名称"
          />
        </div>
        <FieldEditor
          fields={fields}
          setFields={setFields}
          editableKeys={editableKeys}
          setEditableRowKeys={setEditableRowKeys}
        />
      </Modal>
    </div>
  );
};

export default DynamicTablePage;

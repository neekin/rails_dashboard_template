import React, { useState, useEffect } from "react";
import { Button, Form, Input, Modal, message, Popconfirm } from "antd";
import { useParams ,useNavigate} from "react-router";
import { ProTable } from "@ant-design/pro-components";
import { apiFetch } from "@/lib/api/fetch";
const DynamicDataPage = () => {
  const { tableId } = useParams();
  const navigate = useNavigate(); // 用于跳转页面
  const [data, setData] = useState([]);
  const [columns, setColumns] = useState([]);
  const [fields, setFields] = useState([]);
  const [modalVisible, setModalVisible] = useState(false);
  const [editingRecord, setEditingRecord] = useState(null);
  const [form] = Form.useForm();

  const fetchTableData = async (params = {}) => {
    try {
      const response = await apiFetch(
       `/api/dynamic_tables/${tableId}/dynamic_records?query=${JSON.stringify(params)}`
      );
      // const result = await response.json();

      if (response.fields && response.fields.length > 0) {
        const dynamicColumns = response.fields.map((field) => ({
          title: field.name,
          dataIndex: field.name,
          key: field.name,
        }));
        dynamicColumns.push(
          { title: "创建时间", dataIndex: "created_at", key: "created_at" },
          { title: "更新时间", dataIndex: "updated_at", key: "updated_at" },
          {
            title: "操作",
            key: "action",
            render: (_, record) => (
              <>
                <Button
                  type="link"
                  onClick={() => handleEdit(record)}
                >
                  编辑
                </Button>
                <Popconfirm
                  title="确定删除这条记录吗？"
                  onConfirm={() => handleDelete(record.id)}
                >
                  <Button type="link" danger>
                    删除
                  </Button>
                </Popconfirm>
              </>
            ),
          }
        );
        setColumns(dynamicColumns);
        setFields(response.fields);
      }
      console.log(response)
      setData(response.data || []);
    } catch (err) {
      message.error("获取表数据失败");
    }
  };

  const handleSaveData = async (values) => {
    try {
      const method = editingRecord ? "PUT" : "POST";
      const url = editingRecord
        ? `/api/dynamic_tables/${tableId}/dynamic_records/${editingRecord.id}`
        : `/api/dynamic_tables/${tableId}/dynamic_records`;

      const response = await fetch(url, {
        method,
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ record: values }),
      });

      if (response.ok) {
        message.success(editingRecord ? "数据更新成功" : "数据保存成功");
        setModalVisible(false);
        setEditingRecord(null);
        fetchTableData();
      } else {
        message.error(editingRecord ? "数据更新失败" : "数据保存失败");
      }
    } catch (err) {
      message.error(editingRecord ? "数据更新失败" : "数据保存失败");
    }
  };

  const handleDelete = async (id) => {
    try {
      const response = await fetch(
        `/api/dynamic_tables/${tableId}/dynamic_records/${id}`,
        { method: "DELETE" }
      );

      if (response.ok) {
        message.success("数据删除成功");
        fetchTableData();
      } else {
        message.error("数据删除失败");
      }
    } catch (err) {
      message.error("数据删除失败");
    }
  };

  const handleEdit = (record) => {
    setEditingRecord(record);
    form.setFieldsValue(record);
    setModalVisible(true);
  };

  const renderFormItems = () => {
    return fields.map((field) => {
      let inputComponent;
      switch (field.field_type) {
        case "integer":
          inputComponent = <Input type="number" placeholder={`请输入 ${field.name}`} />;
          break;
        case "boolean":
          inputComponent = <Input type="checkbox" style={{ width: "auto" }} />;
          break;
        case "date":
          inputComponent = <Input type="date" />;
          break;
        case "datetime":
          inputComponent = <Input type="datetime-local" />;
          break;
        case "decimal":
        case "float":
          inputComponent = <Input type="number" step="0.01" />;
          break;
        default:
          inputComponent = <Input />;
      }

      const rules = [];
      if (field.required) {
        rules.push({ required: true, message: `${field.name} 是必填项` });
      }

      return (
        <Form.Item key={field.name} label={field.name} name={field.name} rules={rules}>
          {inputComponent}
        </Form.Item>
      );
    });
  };
  const handleCreateFields = () => {
    // 跳转到字段创建页面
    navigate(`/admin/dynamic_fields/${tableId}`);
  };
  useEffect(() => {
  fetchTableData();
  }, [tableId]); // <--- 空数组是关键！
  return (
    <div>
        {fields.length === 0 ? (
        <div style={{ textAlign: "center", marginTop: "20px" }}>
          <p>当前表格尚未创建字段，请先创建字段。</p>
          <Button type="primary" onClick={handleCreateFields}>
            去创建字段
          </Button>
        </div>
      ) : (
        <>
          <ProTable
            rowKey="id"
            columns={columns}
            dataSource={data}
            pagination={{ pageSize: 10 }}
            search={true}
            toolBarRender={() => [
              <Button
                key="add"
                type="primary"
                onClick={() => {
                  setEditingRecord(null);
                  form.resetFields();
                  setModalVisible(true);
                }}
              >
                新增数据
              </Button>,
            ]}
            request={async (params) => {
              await fetchTableData(params);
              return { data, success: true };
            }}
          />
          <Modal
            title={editingRecord ? "编辑数据" : "新增数据"}
            open={modalVisible}
            onCancel={() => setModalVisible(false)}
            footer={[
              <Button key="cancel" onClick={() => setModalVisible(false)}>
                取消
              </Button>,
              <Button
                key="submit"
                type="primary"
                onClick={() => {
                  form.validateFields().then((values) => {
                    handleSaveData(values);
                  });
                }}
              >
                保存
              </Button>,
            ]}
          >
            <Form form={form} layout="vertical">
              {renderFormItems()}
            </Form>
          </Modal>
        </>
      )}
    </div>
  );
};

export default DynamicDataPage;
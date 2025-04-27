import React from "react";
import { Button, Result } from "antd";
import { useNavigate } from "react-router";

const Page403 = () => {
  const navigate = useNavigate();

  const handleBackHome = () => {
    navigate("/"); // 跳转到首页
  };
  return (
    <Result
      status="403"
      title="403"
      subTitle="Sorry, you are not authorized to access this page."
      extra={
        <Button type="primary" onClick={handleBackHome}>
          Back Home
        </Button>
      }
    />
  );
};
export default Page403;

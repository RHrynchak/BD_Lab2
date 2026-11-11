--
-- PostgreSQL database dump
--

\restrict uOIzFrgE2fjiOh7hGavetcXXvqle86O9JQHfaw3iC54ETAV0Y7kXfM4bcHJNo55

-- Dumped from database version 18.1
-- Dumped by pg_dump version 18.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: fn_decreaseinventoryonsale(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_decreaseinventoryonsale() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE "Inventory"
    SET "QuantityAvailable" = "QuantityAvailable" - NEW."Quantity"
    WHERE "ProductId" = NEW."ProductId";
    
    RETURN NEW;
END;
$$;


--
-- Name: fn_updatetimestamp(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_updatetimestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW."UpdatedAt" = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


--
-- Name: fn_validateinventorybeforesale(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_validateinventorybeforesale() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_TotalAvailable INT;
BEGIN
    SELECT COALESCE(SUM("QuantityAvailable"), 0)
    INTO v_TotalAvailable
    FROM "Inventory"
    WHERE "ProductId" = NEW."ProductId";

    IF NEW."Quantity" > v_TotalAvailable THEN
        RAISE EXCEPTION 'Недостатньо товару (ID: %) на складі! В наявності: %, Спроба продати: %', 
                        NEW."ProductId", v_TotalAvailable, NEW."Quantity";
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: sp_addorderitem(integer, integer, integer, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sp_addorderitem(p_orderid integer, p_productid integer, p_quantity integer, p_unitprice numeric) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO "OrderItem" ("OrderId", "ProductId", "Quantity", "UnitPrice")
    VALUES (p_orderid, p_productid, p_quantity, p_unitprice)
    RETURNING "Id" INTO v_id;
    RETURN v_id;
END; $$;


--
-- Name: sp_createcustomer(character varying, character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sp_createcustomer(p_firstname character varying, p_lastname character varying, p_phone character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO "Customer" ("FirstName", "LastName", "Phone")
    VALUES (p_firstname, p_lastname, p_phone)
    RETURNING "Id" INTO v_id;
    RETURN v_id;
END; $$;


--
-- Name: sp_createorder(integer, integer, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sp_createorder(p_customerid integer, p_employeeid integer, p_totalamount numeric) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO "Order" ("CustomerId", "EmployeeId", "OrderDate", "TotalAmount")
    VALUES (p_customerid, p_employeeid, CURRENT_TIMESTAMP, p_totalamount)
    RETURNING "Id" INTO v_id;
    RETURN v_id;
END; $$;


--
-- Name: sp_createproduct(integer, character varying, character varying, character varying, numeric, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sp_createproduct(p_categoryid integer, p_name character varying, p_barcode character varying, p_sku character varying, p_price numeric, p_employeeid integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO "Product" ("CategoryId", "Name", "Barcode", "SKU", "Price", "UpdatedById")
    VALUES (p_categoryid, p_name, p_barcode, p_sku, p_price, p_employeeid)
    RETURNING "Id" INTO v_id;
    RETURN v_id;
END; $$;


--
-- Name: sp_fireemployee(integer, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_fireemployee(IN p_employeetofireid integer, IN p_managerid integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE "Employee"
    SET "IsDeleted" = true,
        "UpdatedById" = p_ManagerId
    WHERE "Id" = p_EmployeeToFireId;
END;
$$;


--
-- Name: sp_getallactivecustomers(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sp_getallactivecustomers() RETURNS TABLE("Id" integer, "FirstName" character varying, "LastName" character varying, "Phone" character varying, "LoyaltyPoints" integer)
    LANGUAGE sql
    AS $$
    SELECT "Id", "FirstName", "LastName", "Phone", "LoyaltyPoints"
    FROM "Customer" WHERE "IsDeleted" = false;
$$;


--
-- Name: sp_getallactiveproducts(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sp_getallactiveproducts() RETURNS TABLE("Id" integer, "Name" character varying, "SKU" character varying, "Price" numeric, "Category" character varying)
    LANGUAGE sql
    AS $$
    SELECT "Id", "Name", "SKU", "Price", "Category" FROM vw_activeproducts;
$$;


--
-- Name: sp_getallorders(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sp_getallorders() RETURNS TABLE("Id" integer, "OrderDate" timestamp without time zone, "TotalAmount" numeric, "CustomerId" integer, "EmployeeId" integer, "CustomerName" text, "CustomerPhone" character varying, "EmployeeName" text)
    LANGUAGE sql
    AS $$
    SELECT "Id", "OrderDate", "TotalAmount", "CustomerId", "EmployeeId", 
           "CustomerName", "CustomerPhone", "EmployeeName"
    FROM vw_orderdetails;
$$;


--
-- Name: sp_getcustomerbyid(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sp_getcustomerbyid(p_id integer) RETURNS TABLE("Id" integer, "FirstName" character varying, "LastName" character varying, "Phone" character varying, "LoyaltyPoints" integer, "IsDeleted" boolean)
    LANGUAGE sql
    AS $$
    SELECT "Id", "FirstName", "LastName", "Phone", "LoyaltyPoints", "IsDeleted"
    FROM "Customer" WHERE "Id" = p_id;
$$;


--
-- Name: sp_getinventorybyproductid(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sp_getinventorybyproductid(p_productid integer) RETURNS TABLE("Id" integer, "Product" character varying, "SKU" character varying, "Department" character varying, "QuantityAvailable" integer)
    LANGUAGE sql
    AS $$
    SELECT v."Id", v."Product", v."SKU", v."Department", v."QuantityAvailable"
    FROM vw_inventorystatus v
    JOIN "Inventory" i ON v."Id" = i."Id"
    WHERE i."ProductId" = p_productid;
$$;


--
-- Name: sp_getinventorystatus(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sp_getinventorystatus() RETURNS TABLE("Id" integer, "Product" character varying, "SKU" character varying, "Department" character varying, "QuantityAvailable" integer)
    LANGUAGE sql
    AS $$
    SELECT "Id", "Product", "SKU", "Department", "QuantityAvailable" 
    FROM vw_inventorystatus;
$$;


--
-- Name: sp_getorderbyid(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sp_getorderbyid(p_id integer) RETURNS TABLE("Id" integer, "OrderDate" timestamp without time zone, "TotalAmount" numeric, "CustomerId" integer, "EmployeeId" integer, "CustomerName" text, "CustomerPhone" character varying, "EmployeeName" text)
    LANGUAGE sql
    AS $$
    SELECT "Id", "OrderDate", "TotalAmount", "CustomerId", "EmployeeId", 
           "CustomerName", "CustomerPhone", "EmployeeName"
    FROM vw_orderdetails WHERE "Id" = p_id;
$$;


--
-- Name: sp_getorderitems(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sp_getorderitems(p_orderid integer) RETURNS TABLE("Id" integer, "OrderId" integer, "ProductId" integer, "Quantity" integer, "UnitPrice" numeric, "ProductName" character varying)
    LANGUAGE sql
    AS $$
    SELECT oi."Id", oi."OrderId", oi."ProductId", oi."Quantity", 
           oi."UnitPrice", p."Name"
    FROM "OrderItem" oi
    JOIN "Product" p ON oi."ProductId" = p."Id"
    WHERE oi."OrderId" = p_orderid;
$$;


--
-- Name: sp_getproductbyid(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sp_getproductbyid(p_id integer) RETURNS TABLE("Id" integer, "CategoryId" integer, "Name" character varying, "Barcode" character varying, "SKU" character varying, "Price" numeric, "IsDeleted" boolean, "UpdatedAt" timestamp without time zone, "UpdatedById" integer)
    LANGUAGE sql
    AS $$
    SELECT "Id", "CategoryId", "Name", "Barcode", "SKU", "Price", 
           "IsDeleted", "UpdatedAt", "UpdatedById"
    FROM "Product" WHERE "Id" = p_id;
$$;


--
-- Name: sp_softdeletecustomer(integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_softdeletecustomer(IN p_id integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE "Customer" SET "IsDeleted" = true WHERE "Id" = p_id;
END; $$;


--
-- Name: sp_softdeleteproduct(integer, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_softdeleteproduct(IN p_productid integer, IN p_employeeid integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE "Product"
    SET "IsDeleted" = true,
        "UpdatedById" = p_EmployeeId
    WHERE "Id" = p_ProductId;
END;
$$;


--
-- Name: sp_updatecustomer(integer, character varying, character varying, character varying, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_updatecustomer(IN p_id integer, IN p_firstname character varying, IN p_lastname character varying, IN p_phone character varying, IN p_loyaltypoints integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE "Customer"
    SET "FirstName" = p_firstname, "LastName" = p_lastname, 
        "Phone" = p_phone, "LoyaltyPoints" = p_loyaltypoints
    WHERE "Id" = p_id;
END; $$;


--
-- Name: sp_updateinventory(integer, integer, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_updateinventory(IN p_id integer, IN p_quantity integer, IN p_employeeid integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE "Inventory"
    SET "QuantityAvailable" = p_quantity, "UpdatedById" = p_employeeid
    WHERE "Id" = p_id;
END; $$;


--
-- Name: sp_updateproduct(integer, integer, character varying, numeric, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_updateproduct(IN p_id integer, IN p_categoryid integer, IN p_name character varying, IN p_price numeric, IN p_employeeid integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE "Product"
    SET "CategoryId" = p_categoryid, "Name" = p_name, 
        "Price" = p_price, "UpdatedById" = p_employeeid
    WHERE "Id" = p_id;
END; $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: Category; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Category" (
    "Id" integer NOT NULL,
    "Name" character varying NOT NULL,
    "ParentCategoryId" integer
);


--
-- Name: Category_Id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public."Category" ALTER COLUMN "Id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."Category_Id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: Customer; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Customer" (
    "Id" integer NOT NULL,
    "FirstName" character varying NOT NULL,
    "LastName" character varying,
    "Phone" character varying NOT NULL,
    "LoyaltyPoints" integer DEFAULT 0 NOT NULL,
    "IsDeleted" boolean DEFAULT false NOT NULL
);


--
-- Name: Customer_Id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public."Customer" ALTER COLUMN "Id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."Customer_Id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: Delivery; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Delivery" (
    "Id" integer NOT NULL,
    "SupplierId" integer NOT NULL,
    "DeliveryDate" timestamp without time zone NOT NULL,
    "TotalAmount" numeric(18,2) NOT NULL
);


--
-- Name: DeliveryItem; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."DeliveryItem" (
    "Id" integer NOT NULL,
    "DeliveryId" integer NOT NULL,
    "ProductId" integer NOT NULL,
    "Quantity" integer NOT NULL,
    "PurchasePrice" numeric(18,2) NOT NULL
);


--
-- Name: DeliveryItem_Id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public."DeliveryItem" ALTER COLUMN "Id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."DeliveryItem_Id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: Delivery_Id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public."Delivery" ALTER COLUMN "Id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."Delivery_Id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: Department; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Department" (
    "Id" integer NOT NULL,
    "StoreId" integer NOT NULL,
    "Name" character varying NOT NULL,
    "Floor" integer NOT NULL
);


--
-- Name: Department_Id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public."Department" ALTER COLUMN "Id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."Department_Id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: Discount; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Discount" (
    "Id" integer NOT NULL,
    "ProductId" integer NOT NULL,
    "Percentage" numeric(18,2) NOT NULL,
    "StartDate" timestamp without time zone NOT NULL,
    "EndDate" timestamp without time zone NOT NULL
);


--
-- Name: Discount_Id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public."Discount" ALTER COLUMN "Id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."Discount_Id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: Employee; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Employee" (
    "Id" integer NOT NULL,
    "DepartmentId" integer NOT NULL,
    "PositionId" integer NOT NULL,
    "FirstName" character varying NOT NULL,
    "LastName" character varying NOT NULL,
    "IsDeleted" boolean DEFAULT false NOT NULL,
    "UpdatedAt" timestamp without time zone,
    "UpdatedById" integer
);


--
-- Name: EmployeeShift; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."EmployeeShift" (
    "Id" integer NOT NULL,
    "EmployeeId" integer NOT NULL,
    "ShiftId" integer NOT NULL,
    "WorkDate" date NOT NULL
);


--
-- Name: EmployeeShift_Id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public."EmployeeShift" ALTER COLUMN "Id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."EmployeeShift_Id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: Employee_Id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public."Employee" ALTER COLUMN "Id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."Employee_Id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: Inventory; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Inventory" (
    "Id" integer NOT NULL,
    "ProductId" integer NOT NULL,
    "DepartmentId" integer NOT NULL,
    "QuantityAvailable" integer NOT NULL,
    "UpdatedAt" timestamp without time zone,
    "UpdatedById" integer
);


--
-- Name: Inventory_Id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public."Inventory" ALTER COLUMN "Id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."Inventory_Id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: Order; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Order" (
    "Id" integer NOT NULL,
    "CustomerId" integer,
    "EmployeeId" integer NOT NULL,
    "OrderDate" timestamp without time zone NOT NULL,
    "TotalAmount" numeric(18,2) NOT NULL
);


--
-- Name: OrderItem; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."OrderItem" (
    "Id" integer NOT NULL,
    "OrderId" integer NOT NULL,
    "ProductId" integer NOT NULL,
    "Quantity" integer NOT NULL,
    "UnitPrice" numeric(18,2) NOT NULL
);


--
-- Name: OrderItem_Id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public."OrderItem" ALTER COLUMN "Id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."OrderItem_Id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: Order_Id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public."Order" ALTER COLUMN "Id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."Order_Id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: Position; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Position" (
    "Id" integer NOT NULL,
    "Title" character varying NOT NULL,
    "BaseSalary" numeric(18,2) NOT NULL
);


--
-- Name: Position_Id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public."Position" ALTER COLUMN "Id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."Position_Id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: Product; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Product" (
    "Id" integer NOT NULL,
    "CategoryId" integer NOT NULL,
    "Name" character varying NOT NULL,
    "Barcode" character varying NOT NULL,
    "SKU" character varying NOT NULL,
    "Price" numeric(18,2) NOT NULL,
    "IsDeleted" boolean DEFAULT false NOT NULL,
    "UpdatedAt" timestamp without time zone,
    "UpdatedById" integer
);


--
-- Name: Product_Id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public."Product" ALTER COLUMN "Id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."Product_Id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: Shift; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Shift" (
    "Id" integer NOT NULL,
    "Name" character varying NOT NULL,
    "StartTime" time without time zone NOT NULL,
    "EndTime" time without time zone NOT NULL
);


--
-- Name: Shift_Id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public."Shift" ALTER COLUMN "Id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."Shift_Id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: Store; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Store" (
    "Id" integer NOT NULL,
    "Name" character varying NOT NULL,
    "Address" character varying NOT NULL
);


--
-- Name: Store_Id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public."Store" ALTER COLUMN "Id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."Store_Id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: Supplier; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Supplier" (
    "Id" integer NOT NULL,
    "CompanyName" character varying NOT NULL,
    "ContactPhone" character varying NOT NULL,
    "IsDeleted" boolean DEFAULT false NOT NULL
);


--
-- Name: Supplier_Id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public."Supplier" ALTER COLUMN "Id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."Supplier_Id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: vw_activeemployees; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_activeemployees AS
 SELECT e."Id",
    e."FirstName",
    e."LastName",
    pos."Title" AS "Position",
    d."Name" AS "Department"
   FROM ((public."Employee" e
     JOIN public."Position" pos ON ((e."PositionId" = pos."Id")))
     JOIN public."Department" d ON ((e."DepartmentId" = d."Id")))
  WHERE (e."IsDeleted" = false);


--
-- Name: vw_activeproducts; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_activeproducts AS
 SELECT p."Id",
    p."Name",
    p."SKU",
    p."Price",
    c."Name" AS "Category"
   FROM (public."Product" p
     JOIN public."Category" c ON ((p."CategoryId" = c."Id")))
  WHERE (p."IsDeleted" = false);


--
-- Name: vw_inventorystatus; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_inventorystatus AS
 SELECT i."Id",
    p."Name" AS "Product",
    p."SKU",
    d."Name" AS "Department",
    i."QuantityAvailable"
   FROM ((public."Inventory" i
     JOIN public."Product" p ON ((i."ProductId" = p."Id")))
     JOIN public."Department" d ON ((i."DepartmentId" = d."Id")))
  WHERE (p."IsDeleted" = false);


--
-- Name: vw_orderdetails; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_orderdetails AS
 SELECT o."Id",
    o."OrderDate",
    o."TotalAmount",
    o."CustomerId",
    o."EmployeeId",
    COALESCE((((c."FirstName")::text || ' '::text) || (COALESCE(c."LastName", ''::character varying))::text), 'Без клієнта'::text) AS "CustomerName",
    c."Phone" AS "CustomerPhone",
    (((e."FirstName")::text || ' '::text) || (e."LastName")::text) AS "EmployeeName"
   FROM ((public."Order" o
     LEFT JOIN public."Customer" c ON ((o."CustomerId" = c."Id")))
     JOIN public."Employee" e ON ((o."EmployeeId" = e."Id")));


--
-- Name: Category Category_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Category"
    ADD CONSTRAINT "Category_pkey" PRIMARY KEY ("Id");


--
-- Name: Customer Customer_Phone_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Customer"
    ADD CONSTRAINT "Customer_Phone_key" UNIQUE ("Phone");


--
-- Name: Customer Customer_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Customer"
    ADD CONSTRAINT "Customer_pkey" PRIMARY KEY ("Id");


--
-- Name: DeliveryItem DeliveryItem_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."DeliveryItem"
    ADD CONSTRAINT "DeliveryItem_pkey" PRIMARY KEY ("Id");


--
-- Name: Delivery Delivery_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Delivery"
    ADD CONSTRAINT "Delivery_pkey" PRIMARY KEY ("Id");


--
-- Name: Department Department_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Department"
    ADD CONSTRAINT "Department_pkey" PRIMARY KEY ("Id");


--
-- Name: Discount Discount_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Discount"
    ADD CONSTRAINT "Discount_pkey" PRIMARY KEY ("Id");


--
-- Name: EmployeeShift EmployeeShift_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EmployeeShift"
    ADD CONSTRAINT "EmployeeShift_pkey" PRIMARY KEY ("Id");


--
-- Name: Employee Employee_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Employee"
    ADD CONSTRAINT "Employee_pkey" PRIMARY KEY ("Id");


--
-- Name: Inventory Inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Inventory"
    ADD CONSTRAINT "Inventory_pkey" PRIMARY KEY ("Id");


--
-- Name: OrderItem OrderItem_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."OrderItem"
    ADD CONSTRAINT "OrderItem_pkey" PRIMARY KEY ("Id");


--
-- Name: Order Order_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Order"
    ADD CONSTRAINT "Order_pkey" PRIMARY KEY ("Id");


--
-- Name: Position Position_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Position"
    ADD CONSTRAINT "Position_pkey" PRIMARY KEY ("Id");


--
-- Name: Product Product_Barcode_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Product"
    ADD CONSTRAINT "Product_Barcode_key" UNIQUE ("Barcode");


--
-- Name: Product Product_SKU_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Product"
    ADD CONSTRAINT "Product_SKU_key" UNIQUE ("SKU");


--
-- Name: Product Product_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Product"
    ADD CONSTRAINT "Product_pkey" PRIMARY KEY ("Id");


--
-- Name: Shift Shift_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Shift"
    ADD CONSTRAINT "Shift_pkey" PRIMARY KEY ("Id");


--
-- Name: Store Store_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Store"
    ADD CONSTRAINT "Store_pkey" PRIMARY KEY ("Id");


--
-- Name: Supplier Supplier_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Supplier"
    ADD CONSTRAINT "Supplier_pkey" PRIMARY KEY ("Id");


--
-- Name: idx_delivery_date_brin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_delivery_date_brin ON public."Delivery" USING brin ("DeliveryDate");


--
-- Name: idx_employee_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_active ON public."Employee" USING btree ("Id") WHERE ("IsDeleted" = false);


--
-- Name: idx_inventory_product_department; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_product_department ON public."Inventory" USING btree ("ProductId", "DepartmentId");


--
-- Name: idx_inventory_productid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_productid ON public."Inventory" USING btree ("ProductId");


--
-- Name: idx_order_customerid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_order_customerid ON public."Order" USING btree ("CustomerId");


--
-- Name: idx_order_date_brin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_order_date_brin ON public."Order" USING brin ("OrderDate");


--
-- Name: idx_orderitem_orderid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orderitem_orderid ON public."OrderItem" USING btree ("OrderId");


--
-- Name: idx_product_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_active ON public."Product" USING btree ("Id") WHERE ("IsDeleted" = false);


--
-- Name: idx_product_barcode_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_barcode_hash ON public."Product" USING hash ("Barcode");


--
-- Name: idx_product_categoryid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_categoryid ON public."Product" USING btree ("CategoryId");


--
-- Name: idx_product_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_name ON public."Product" USING btree ("Name");


--
-- Name: Employee trg_employee_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_employee_audit BEFORE UPDATE ON public."Employee" FOR EACH ROW EXECUTE FUNCTION public.fn_updatetimestamp();


--
-- Name: Inventory trg_inventory_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_inventory_audit BEFORE UPDATE ON public."Inventory" FOR EACH ROW EXECUTE FUNCTION public.fn_updatetimestamp();


--
-- Name: OrderItem trg_orderitem_sale; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_orderitem_sale AFTER INSERT ON public."OrderItem" FOR EACH ROW EXECUTE FUNCTION public.fn_decreaseinventoryonsale();


--
-- Name: OrderItem trg_orderitem_validate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_orderitem_validate BEFORE INSERT ON public."OrderItem" FOR EACH ROW EXECUTE FUNCTION public.fn_validateinventorybeforesale();


--
-- Name: Product trg_product_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_product_audit BEFORE UPDATE ON public."Product" FOR EACH ROW EXECUTE FUNCTION public.fn_updatetimestamp();


--
-- Name: Category Category_ParentCategoryId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Category"
    ADD CONSTRAINT "Category_ParentCategoryId_fkey" FOREIGN KEY ("ParentCategoryId") REFERENCES public."Category"("Id") DEFERRABLE;


--
-- Name: DeliveryItem DeliveryItem_DeliveryId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."DeliveryItem"
    ADD CONSTRAINT "DeliveryItem_DeliveryId_fkey" FOREIGN KEY ("DeliveryId") REFERENCES public."Delivery"("Id") DEFERRABLE;


--
-- Name: DeliveryItem DeliveryItem_ProductId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."DeliveryItem"
    ADD CONSTRAINT "DeliveryItem_ProductId_fkey" FOREIGN KEY ("ProductId") REFERENCES public."Product"("Id") DEFERRABLE;


--
-- Name: Delivery Delivery_SupplierId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Delivery"
    ADD CONSTRAINT "Delivery_SupplierId_fkey" FOREIGN KEY ("SupplierId") REFERENCES public."Supplier"("Id") DEFERRABLE;


--
-- Name: Department Department_StoreId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Department"
    ADD CONSTRAINT "Department_StoreId_fkey" FOREIGN KEY ("StoreId") REFERENCES public."Store"("Id") DEFERRABLE;


--
-- Name: Discount Discount_ProductId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Discount"
    ADD CONSTRAINT "Discount_ProductId_fkey" FOREIGN KEY ("ProductId") REFERENCES public."Product"("Id") DEFERRABLE;


--
-- Name: EmployeeShift EmployeeShift_EmployeeId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EmployeeShift"
    ADD CONSTRAINT "EmployeeShift_EmployeeId_fkey" FOREIGN KEY ("EmployeeId") REFERENCES public."Employee"("Id") DEFERRABLE;


--
-- Name: EmployeeShift EmployeeShift_ShiftId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."EmployeeShift"
    ADD CONSTRAINT "EmployeeShift_ShiftId_fkey" FOREIGN KEY ("ShiftId") REFERENCES public."Shift"("Id") DEFERRABLE;


--
-- Name: Employee Employee_DepartmentId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Employee"
    ADD CONSTRAINT "Employee_DepartmentId_fkey" FOREIGN KEY ("DepartmentId") REFERENCES public."Department"("Id") DEFERRABLE;


--
-- Name: Employee Employee_PositionId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Employee"
    ADD CONSTRAINT "Employee_PositionId_fkey" FOREIGN KEY ("PositionId") REFERENCES public."Position"("Id") DEFERRABLE;


--
-- Name: Employee Employee_UpdatedById_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Employee"
    ADD CONSTRAINT "Employee_UpdatedById_fkey" FOREIGN KEY ("UpdatedById") REFERENCES public."Employee"("Id") DEFERRABLE;


--
-- Name: Inventory Inventory_DepartmentId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Inventory"
    ADD CONSTRAINT "Inventory_DepartmentId_fkey" FOREIGN KEY ("DepartmentId") REFERENCES public."Department"("Id") DEFERRABLE;


--
-- Name: Inventory Inventory_ProductId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Inventory"
    ADD CONSTRAINT "Inventory_ProductId_fkey" FOREIGN KEY ("ProductId") REFERENCES public."Product"("Id") DEFERRABLE;


--
-- Name: Inventory Inventory_UpdatedById_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Inventory"
    ADD CONSTRAINT "Inventory_UpdatedById_fkey" FOREIGN KEY ("UpdatedById") REFERENCES public."Employee"("Id") DEFERRABLE;


--
-- Name: OrderItem OrderItem_OrderId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."OrderItem"
    ADD CONSTRAINT "OrderItem_OrderId_fkey" FOREIGN KEY ("OrderId") REFERENCES public."Order"("Id") DEFERRABLE;


--
-- Name: OrderItem OrderItem_ProductId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."OrderItem"
    ADD CONSTRAINT "OrderItem_ProductId_fkey" FOREIGN KEY ("ProductId") REFERENCES public."Product"("Id") DEFERRABLE;


--
-- Name: Order Order_CustomerId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Order"
    ADD CONSTRAINT "Order_CustomerId_fkey" FOREIGN KEY ("CustomerId") REFERENCES public."Customer"("Id") DEFERRABLE;


--
-- Name: Order Order_EmployeeId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Order"
    ADD CONSTRAINT "Order_EmployeeId_fkey" FOREIGN KEY ("EmployeeId") REFERENCES public."Employee"("Id") DEFERRABLE;


--
-- Name: Product Product_CategoryId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Product"
    ADD CONSTRAINT "Product_CategoryId_fkey" FOREIGN KEY ("CategoryId") REFERENCES public."Category"("Id") DEFERRABLE;


--
-- Name: Product Product_UpdatedById_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Product"
    ADD CONSTRAINT "Product_UpdatedById_fkey" FOREIGN KEY ("UpdatedById") REFERENCES public."Employee"("Id") DEFERRABLE;


--
-- PostgreSQL database dump complete
--

\unrestrict uOIzFrgE2fjiOh7hGavetcXXvqle86O9JQHfaw3iC54ETAV0Y7kXfM4bcHJNo55

